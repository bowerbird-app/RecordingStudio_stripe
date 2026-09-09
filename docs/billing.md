# How billing works

Stripe is the source of truth for Products, Prices, Customers, Subscriptions, invoices, and cards. This gem keeps a thin local projection so a workspace can answer usage questions without a Stripe round trip.

## Data

| Thing | Where it lives |
| --- | --- |
| Product, Price | Stripe, copied into `recording_studio_stripe_products` / `_prices` |
| Customer | Stripe Customer id on the workspace root. One Customer per workspace |
| Subscription | Stripe Subscription, plus a local status, period, and plan group |
| Meter | Local named counter (`ai_tokens`, `api_calls`) |
| Usage | Append-only `recording_studio_stripe_usage_entries` |
| Extra packs | `recording_studio_stripe_allowance_purchases` after Checkout |
| Invoices, cards | Stripe Customer Portal. Not copied locally |
| Paywall | Local named feature (`generate_image`). Staff tick them on a plan Product |
| Limit | Config name plus Product metadata (`limit_press_kits`). Count of live recordings of that type |

Usage is a fact table, not a Recording. High volume stays off the tree. Paywalls and limits are not Recordings either.

## Products and Prices

Stripe's shape is the shape here. A **Product** is the plan or pack. A **Price** is one way to pay for it.

Starter is one Product. Monthly and yearly are two Prices on that Product. Extra token packs are a separate Product with one-time Prices.

`/plans` groups by Product. A Monthly / Yearly toggle picks which Price each card shows. When the host sets `config.subscription_types`, `/plans` also sections those Products by group. Type names (Studio, Inbox) only show when more than one type actually has Products. Admin Products is one row per Product, with Add Price. Admin Prices lists every Price with the Product name, and filters by Product or interval.

Cards sort cheapest first for the interval on the page. Groups follow the host’s `subscription_types` map order. Dummy Studio is Starter, Pro, then Team. Extra packs (one-time Prices) are cheapest first too.

Included usage lives on the Price, not the Product. Two Prices on Starter can include different amounts, though dummy uses the same numbers for month and year. Paywalls and standing limits live on the Product, so monthly and yearly Pro share the same features and the same press-kit cap.

## Plan cards

`/plans` and `/pricing` cards are generated from those connections. They are not a handwritten bullet list.

1. Standing caps on the Product (`limit_press_kits`)
2. Included meters on the Price (`included_ai_tokens`)
3. Paywalls ticked on the Product
4. Optional extra lines on the Product (`metadata["plan_card"]`)

The host sets copy and icons once per name:

```ruby
config.limits = {
  "press_kits" => {
    "label" => "Press kits",
    "recordable_type" => "PressKit",
    "subscription_type" => "studio",
    "icon" => "rectangle-stack",
    "plan_line" => "%{quantity} press kits"
  }
}
config.meters = {
  "ai_tokens" => { "label" => "AI tokens", "icon" => "sparkles", "plan_line" => "%{quantity} AI tokens each period" }
}
config.paywalls = {
  "generate_image" => { "label" => "Generate an image", "icon" => "photo" }
}
```

Omit `plan_line` and the card uses the default (`3 press kits`, `1m ai tokens`, or the paywall label). `%{quantity}` is shortened the same way as billing (`1m`, `10k`). Icons are Flatpack / Heroicon names. Missing icon is a check.

Per-plan control lives on the Product as `plan_card` metadata. It stays local. Stripe metadata is strings only, so this hash is not sent to Stripe. Webhooks keep the local card when they upsert a Product.

```json
{
  "hide": ["meter:api_calls"],
  "order": ["limit:press_kits", "meter:ai_tokens", "paywall:generate_image", "extra:priority"],
  "extras": [
    { "key": "priority", "text": "Someone picks up the phone", "icon": "phone" }
  ]
}
```

Keys are `limit:<name>`, `meter:<name>`, `paywall:<name>`, `extra:<key>`. Blank `order` is caps, then usage, then features, then extras. Hide omits a line from the card; the cap, meter, or paywall still bills and gates. Extras are display-only. Admin new plan and edit screens put those card controls in a Pricing card disclosure. The extra line is what the card says plus an icon. The key stays hidden and is filled from the text when blank.

The card is a Flatpack list with an icon on each line. Dummy Team also shows “Someone picks up the phone”. Cards in a group share one height. Choose, Upgrade, and Current sit in the card footer, so extra space sits between the last line and the action. A Studio row and an Inbox row can still differ from each other.

## Plan groups

A workspace has one Stripe Customer. It can hold one live plan per named group.

```ruby
RecordingStudioStripe.configure do |config|
  config.subscription_types = {
    "studio" => { "label" => "Studio" },
    "inbox" => { "label" => "Inbox" }
  }
end
```

Omit that map and the gem keeps one implied group (`plan`) and one live plan, which is today's behaviour.

Each plan Product belongs to one group. Starter, Pro, and Team share `studio`. Inbox Products share `inbox`. Checkout for an empty group adds a Stripe Subscription on the same Customer. A different Product in a group you already have opens a confirmation page, then upgrades now or downgrades at renewal. Cancel stops that group only. Manage billing on Stripe stays one button. Stripe shows every Subscription for the Customer.

```ruby
account.billing.line(:studio).subscription
account.billing.line(:studio).meter(:ai_tokens).remaining
account.billing.unlocked?(:export_csv)
account.billing.line(:inbox).unlocked?(:export_csv)
```

`unlocked?` is true if any live plan opens that paywall. `line(:inbox).unlocked?` is the scoped check. A `past_due` plan still counts as subscribed.

Meters must go through a line when two plans include the same meter and their periods differ. `account.billing.meter(:ai_tokens)` picks the live plan that includes that meter. `account.billing.subscription` is still the latest live plan. Dummy seeds Studio and Inbox so you can click both.

Existing rows get type `plan`. If you configure exactly one type, `AssignSubscriptionTypes` remaps `plan` to that key on boot. If you configure more than one, assign each Product in Admin.

## Meters

A meter is a named counter the host records against. Defaults are `ai_tokens` and `api_calls`. The host replaces or extends that map:

```ruby
RecordingStudioStripe.configure do |config|
  config.meters = {
    "ai_tokens" => { "label" => "AI tokens", "icon" => "sparkles" },
    "api_calls" => { "label" => "API calls", "icon" => "bolt" },
    "seats" => { "label" => "Seats" }
  }
end
```

The gem writes those rows on boot. Staff can also add a meter in Admin. `Meter.named` finds a row. It does not create one. Then:

```ruby
account.billing.meter(:seats).record(1)
```

A plan Price nominates how many of each meter it includes with `included_<meter_name>` metadata. Zero or missing means that meter is not part of the plan. The New Price form shows one included field per meter. Edit Price changes those amounts. Allowance packs name a meter and a quantity on a one-time Price (`meter`, `allowance`).

```ruby
account.billing.line(:studio).meter(:ai_tokens).spend(1)
```

`spend` raises `MeterLimitReached` when remaining is too small (HTML goes to `/billing`; JSON is 403). A retry with the same idempotency key returns the first row. `record` writes the fact even when over, for work that already ran.

## Paywalls

A paywall is a named feature the host checks before a job. Hosts register names only:

```ruby
RecordingStudioStripe.configure do |config|
  config.paywalls = {
    "generate_image" => { "label" => "Generate an image", "icon" => "photo" },
    "export_csv" => { "label" => "Export CSV", "icon" => "table-cells" }
  }
end
```

The gem writes those rows on boot. Staff can add more in Admin. Then tick which paywalls a **Product** opens on New plan or Edit. Do not put them on a Price. Extra packs skip this.

The gem registers each paywall as an Accessible named action. The policy is `:view` on the recording **and** a live plan Product includes that paywall:

```ruby
RecordingStudioAccessible.authorized_action?(
  actor: current_user,
  action: :generate_image,
  recording: current_root_recording
)
```

Meter spend stays `available?` / `record`. Buying a plan does not grant `:admin`. Paywalls are not Stripe Entitlements and not a `plan_id` on User.

Dummy registers `generate_image` and `export_csv`, and ticks `generate_image` on Pro and Team.

## Limits

A limit is how many of a recordable type can exist under the workspace right now. It is not a meter. Meters spend this Stripe period and reset. Limits count live recordings of that type (not trashed) and do not reset.

```ruby
RecordingStudioStripe.configure do |config|
  config.limits = {
    "press_kits" => {
      "label" => "Press kits",
      "recordable_type" => "PressKit",
      "subscription_type" => "studio",
      "icon" => "rectangle-stack",
      "plan_line" => "%{quantity} press kits"
    }
  }
end
```

Omit that map and the gem never gates creates. The number lives on the **Product** as `limit_<name>` metadata, so monthly and yearly of the same plan share it. Missing or 0 means none on that plan. Admin New plan and Edit show one integer field per configured limit.

```ruby
kits = account.billing.limit(:press_kits)
kits.included
kits.used
kits.remaining
kits.available?(1)
kits.over?
```

`line(:studio).limit(:press_kits)` is the same handle scoped to that group's live plan. `used` is `Recording.for_root(workspace).of_type("PressKit")` where `trashed_at` is nil. Nested recordings of that type share the cap.

Creating another of that type is blocked at the Recording. `revise` does not consume a slot. Restore from trash does, because used ignores trashed rows. Moving a live row into a full workspace does too. The gate only runs when the destination root enabled `:stripe`. The gem raises `RecordingStudioStripe::PlanLimitReached`. HTML redirects to `/plans`, or `config.limit_reached_path`. JSON is 403 `{ "code": "plan_limit_reached" }`. Dummy copy: “Pick a plan to add press kits.” or “Starter includes 3 press kits. Upgrade, or archive one.” Recording Studio core still swallows `before_record` errors, so the gate is `Recording` `before_create` (and restore, and move) until core can deny `record!`.

Downgrades do not delete extras. `over?` is true and `available?` is false until they archive. Accessible stays access. Do not `record` usage for these caps.

Dummy seeds Starter at 3, Pro at 10, and Team at 25 on Studio. Inbox plans do not include press kits. `/billing` shows the standing cap as a progress bar. Dummy `/press_kits` is the product screen that lists kits and adds them. Plan cards on `/plans` and `/pricing` list those caps, included usage, and ticked features, with icons from the host config.

## Remaining

For that plan's subscription period:

```text
remaining = included + purchased - usage
```

Included comes from Price metadata. Purchased comes from allowance packs bought from the start of that period’s calendar month through period end. Usage is what the app recorded for that plan group. Postgres takes an advisory lock around spend and standing-cap creates. Other databases skip the lock.

## Plan changes

- Higher monthly amount: confirmation page first, then update the Stripe Subscription now, `proration_behavior: always_invoice`, `payment_behavior: error_if_incomplete`. Local Price waits for the webhook
- Lower monthly amount: confirmation page first, then keep the current Price, store `scheduled_price`. Stripe gets a schedule created from the Subscription, then an update with every current item copied into both phases. An existing schedule is released first. A failed schedule does not change the live Price
- Cancel: `cancel_at_period_end` on that group's Subscription. Pass `subscription_type` when more than one live plan exists
- Checkout for a group that already has a live plan opens the confirmation page. It does not apply the change, and it does not open a second Stripe Subscription. A first Checkout in an empty group reserves an incomplete local row so a second attempt cannot mint another Stripe Subscription

## Screens

Customer UI is a mountable engine slice at `/plans` and `/billing`. Dummy home is the host hub: Flatpack `SidebarLayout`, rounded theme. Dummy product screens use Flatpack's rounded theme. `/plans` puts monthly and yearly pills under each plan group name when more than one type has Products, left aligned, above that group's cards. Upgrade and Switch at renewal open `/billing/subscription/change`, which asks you to confirm the new price and when it takes effect. Confirm PATCHes the subscription. A host with one implied type still uses `?interval=year`. Several types use `?interval[studio]=year` so Inbox can stay monthly. `RecordingStudioStripe::PlanIntervals` builds those hrefs. Close on those pages goes to the host home (`main_app.root_path`). The back chevron is browser history, so Close is the way out of the slice.

`/billing` shows **Manage billing on Stripe** above the plan cards when the workspace has a Customer and the actor can `:admin`. Each live plan group gets its own card. Standing caps sit with that group's meters, not on the plan card. Cap cards show used of included, including when over. Usage cards show percent used this period. Meter bars stay quiet when nothing is included yet. `/billing?checkout=ok` explains the wait when Stripe has not written the subscription yet. That POST creates a Stripe Billing Portal session and redirects there. The return URL is the billing page (`success_path`). `:view` can read `/billing` and cannot open the portal. `:edit` cannot pay. Hosts turn the portal on in the Stripe Dashboard. Do not link to dashboard.stripe.com. Do not copy invoices or cards into local tables.

`RecordingStudioStripe::PlansComponent` is the reusable plans block. Pass `groups:` from `Catalog.plan_groups` when types are configured, with each group's own interval hrefs from `PlanIntervals`. Pass `align: :left` on a signed-in billing page and `align: :center` on a public pricing page. Center also centers the title and subtitle. Dummy `/plans` is left. Dummy `/pricing` is centered and does not require a login. Each group's cards sit in a Flatpack Grid that stretches them to one height. Each card is a Flatpack list of caps, included usage, ticked features, and any extra lines on that Product, with the action in the footer. Staff use Recording Studio Admin. The gem registers one `:stripe` section with screens for Products, Prices, Meters, Paywalls, Customers, and Subscriptions. Mutation forms (new plan, Price, Meter, Paywall, and edit plan) live on the billing engine and link from those screens. Edit names the plan, groups features with caps, and tucks pricing-card lines into a disclosure. Dummy's Admin button switches onto the Studio Admin root first. Admin authorizes against that root, not the workspace you were billing.

## Local mode

When `STRIPE_SECRET_KEY` is blank, Checkout writes a local Customer and Subscription (or allowance purchase) and returns the success URL. Dummy uses this so you can click through without Stripe keys. Unsigned webhook JSON is accepted only in that local mode. Do not deploy local mode on a public host. When Stripe is configured, `STRIPE_WEBHOOK_SECRET` is required. A handler that cannot apply yet returns 503 and leaves the event unstored so Stripe can retry. Webhook rows store the event id, type, created, and object id. They do not store the full Stripe object.

Hosts that do not use `current_user` set `config.current_actor`. Hosts that do not use `current_root_recording` set `config.current_root_recording`. `draw_recording_studio_stripe at:` overwrites `config.mount_path`. If Accessible is not loaded, set `config.authenticate` or every billing money action is forbidden.

Recurring Checkout sessions send a new idempotency key each attempt. One-time pack Checkout does the same. Promotion codes are on. Set `config.automatic_tax = true` after Stripe Tax is on in the Dashboard. Checkout then also asks Stripe for the customer address.

Manage billing on Stripe still shows after a local checkout so hosts can see the control. The POST does not call Stripe. It redirects back to `/billing` with a flash.

## What this gem does not do

Stripe keeps invoices, cards, tax, and proration. This gem does not wrap other processors, invent wallets, or use Stripe Entitlements as a second catalogue. Plan features are paywall rows ticked on the Product. Do not copy invoices or payment methods locally.
