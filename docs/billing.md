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
| Limit | Config name plus Product metadata (`limit_press_kits`). A standing count of live recordings, or a standing quantity supplied by the host |

Usage is a fact table, not a Recording. High volume stays off the tree. Paywalls and limits are not Recordings either.

## Products and Prices

Stripe's shape is the shape here. A **Product** is the plan or pack. A **Price** is one way to pay for it.

Starter is one Product. Weekly, monthly, and yearly are Prices on that Product, one per interval. Extra token packs are a separate Product with one-time Prices.

`/plans` groups by Product. A Weekly / Monthly / Yearly toggle picks which Price each card shows. The toggle is a FlatPack pill with `track: true` and `style: :primary`. Its track sets `--tabs-pill-list-background-color` to the surface background, so both pills stay readable on a photo. A pill appears only when that group has a Price for it, and the row lists only Products that have that Price. `stripe_plan_intervals(products)` is that list. Pass `intervals:` on `PlansComponent`, for example `%w[month year]`, to limit it further. A requested interval with no Price in that list uses the first interval that has one. When the host sets `config.subscription_types`, `/plans` also sections those Products by group. Type names (Studio, Inbox) only show when more than one type actually has Products. Admin Products is one row per Product, with Add Price. Admin Prices lists every Price with the Product name, and filters by Product or interval (`week`, `month`, or `year`).

Cards sort cheapest first for the interval on the page. Groups follow the host’s `subscription_types` map order. Dummy Studio is Starter, Pro, then Team. Extra packs (one-time Prices) still sort cheapest first if a host lists them.

Included usage lives on the Price, not the Product. Two Prices on Starter can include different amounts, though dummy uses the same numbers for month and year. Paywalls and standing limits live on the Product, so monthly and yearly Pro share the same features and the same press-kit cap.

## Paid trials

A plan Product can offer a trial. Set trial days and a one-time amount in cents on the Product. 0 cents is a free trial on the same path.

```ruby
RecordingStudioStripe::AssignTrial.call(product: pro, days: 14, unit_amount: 100)
pro.trial.offered?
pro.trial.checkout_label # "Try now"
pro.trial.duration_label # "14 day trial"
pro.trial.amount_label # "$1"
```

`AssignTrial` writes `trial_days` and `trial_unit_amount` on Product metadata. When the amount is above 0 it creates a one-time Price on that same Product with `kind=trial_fee`. That is not an extra pack and not a second monthly Price. `Product#monthly_price` stays the paid monthly Price.

Checkout for a group with no live plan starts the real plan Price. It sends Stripe `trial_period_days`, `payment_method_collection: always`, and the fee line item when a fee Price exists. Metadata `price_id` stays the plan Price so webhooks still project that Price. Status is `trialing`. When the window ends, Stripe invoices the plan Price.

Empty trial days in Admin clears the trial and deactivates fee Prices. Stripe Prices cannot change `unit_amount`, so a new amount deactivates the old fee Price and creates another. Create and Update send `trial_days` and `trial_unit_amount` on Stripe Product metadata. `UpsertProduct` keeps those keys when a webhook omits them, the same way it keeps local `plan_card`.

A workspace that already has a live plan in that group still upgrades or downgrades. Dummy Pro is 14 days and 100 cents.

## Layout

`config.layout` is the layout for this engine. `nil` follows `RecordingStudio.configuration.layout`, then `"recording_studio/default_layout"`. A String names a layout. `false` skips the layout. A callable takes `controller:` and returns a String, `nil`, or `false`.

Engine controllers call `recording_studio_layout { RecordingStudioStripe.configuration.layout }`. The default template reads `content_for :title` and `content_for :subtitle` and draws one page heading. `flat_pack_page_nav` sets back and close. `register_page_nav` and `content_for :page_nav_right` fill the right side of the top nav. `/plans` centers its title and subtitle in `PlansComponent` and does not set `content_for :title`.

`recording_studio_background_image(url)` writes `content_for :background_image`. The default layout passes that URL to `FlatPack::PageLayout` as a decorative image (`alt=""`, `loading="lazy"`). A blank URL leaves the page unchanged. `/plans` passes `config.plans_background_image`. That setting defaults to nil. `recording_studio_page_width(:wide)` writes `content_for :page_width`. Allowed values are `:narrow`, `:default`, `:wide`, and `:full`. A blank value stays `:default`. A host layout that replaces the default reads `content_for(:background_image)` and `content_for(:page_width)`.

## Plan cards

Customer chrome on `/plans`, `/billing`, `/billing/usage`, change, and cancel is `recording_studio.stripe.*` I18n. Staff Admin form views, flashes, and resolvable Definitions chrome (titles, buttons, link text, widget titles/info) use `recording_studio.stripe.admin.*`. The gem ships English. Hosts add other languages. Product names, prices, card subtitles, and `plan_line` text stay as stored. Admin screen/section subtitles, table column headers, and cell values stay English literals. This gem never shipped a top-level `recording_studio_stripe.*` locale namespace.

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
  "subtitle": "For the usual week",
  "hide": ["meter:api_calls"],
  "order": ["limit:press_kits", "meter:ai_tokens", "paywall:generate_image", "extra:priority"],
  "extras": [
    { "key": "priority", "text": "Someone picks up the phone", "icon": "phone" }
  ]
}
```

Keys are `limit:<name>`, `meter:<name>`, `paywall:<name>`, `extra:<key>`. Blank `order` is caps, then usage, then features, then extras. Hide omits a line from the card; the cap, meter, or paywall still bills and gates. Extras are display-only. `subtitle` is one line under the plan name. Blank leaves the name on its own. A missing Price still says "No week Price yet", "No month Price yet", or "No year Price yet" when a host renders that card directly. The plans page leaves that Product off the interval instead. Admin new plan and edit screens put Subtitle next to the name. The rest of the card controls sit in a Pricing card disclosure. The extra line is what the card says plus an icon. The key stays hidden and is filled from the text when blank. Read the line with `product.card_subtitle`.

The card is a Flatpack list with an icon on each line. Dummy Team also shows “Someone picks up the phone”. On `/plans`, `PlansComponent` defaults to `density: :auto`. On a phone each plan is a compact row. The name stays on one line. A marketing subtitle hides. A missing Price still says "No week Price yet", "No month Price yet", or "No year Price yet". The amount is smaller than the desktop price. The button stays medium and only as wide as its label. Features sit under What’s included, closed, until someone opens them. On `density: :auto` that disclosure is a native `details` sibling of the feature list (`peer` / `group`), so the list can stay closed below `md` and stay visible from `md`. Collapse cannot do that in one copy: it hides the panel with `[hidden]`, which preflight makes `display: none !important`. `density: :rows` uses FlatPack Collapse instead (`id: plan-included-<product-id>-<interval>`, `open: false`, `border: false`); the list lives in `#{id}-content[hidden]` until opened. `density: :cards` has no disclosure. From the `md` breakpoint the group is a Flatpack grid again (two columns, then three from `lg`). Cards in a group share one height through four subgrid rows. Row one is the name and subtitle. Row two is the price, at the h2 title size. A trial badge sits in that same row, above the amount. Amounts sit at the bottom of the row so they line up. Extra trial padding sits above the amount. On a phone the badge sits after the plan name, and the price row has a little vertical padding. Row three is the button. The action cell is a column that starts at the top of that shared row. Checkout is one form around a single Flatpack submit button. Current, Upgrade, and Downgrade sit in the same outer box, so those labels share one Y. Row four is the feature list, open. The plans grid sets a 1rem row gap. Every price block uses `md:pb-4`. A trial offer also uses `md:pt-8 md:gap-4`. A card with no Price keeps the four rows and leaves the price and button rows empty. `density: :cards` keeps this tall card on a phone too. `density: :rows` keeps the compact row at every width. Week is `/wk`. Month is `/mo`. Year is `/yr`. A Studio row and an Inbox row can still differ from each other. When the Product offers a trial and the workspace has no live plan in that group, the plan price is struck through with its interval (`$29/mo`), and the trial amount sits beside it with the word trial (`$1 trial`). A badge names the length (14 day trial, 1 month trial), and the button says Try now. A $0 trial still says Try now and shows `$0 trial`. `/wk`, `/mo`, and `/yr` sit against the amount, with no gap. Changing plans keeps Upgrade or Downgrade and the plan price.

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

`unlocked?` is true if any live plan opens that paywall. `line(:inbox).unlocked?` is the scoped check. A `past_due` plan still counts as subscribed. Billing tells people the card failed and sends them to Stripe to update it.

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

The gem writes those rows on boot. Names come from this map only. DB-only meters are removed on boot. `Meter.named` finds a row. It does not create one. Then:

```ruby
account.billing.meter(:seats).record(1)
```

A plan Price nominates how many of each meter it includes with `included_<meter_name>` metadata. Zero or missing means that meter is not part of the plan. The New Price form shows one included field per meter. Edit Price changes those amounts. Allowance packs name a meter and a quantity on a one-time Price (`meter`, `allowance`).

```ruby
account.billing.line(:studio).meter(:ai_tokens).spend(1)
```

`spend` raises `MeterLimitReached` when remaining is too small (HTML goes to `/billing/usage`; JSON is 403). A retry with the same idempotency key returns the first row. `record` writes the fact even when over, for work that already ran.

## Weighted credits

Credits are a normal meter named `credits`. The host names the billable operations and what each one costs. The gem does not ship provider keys.

```ruby
RecordingStudioStripe.configure do |config|
  config.meters = {
    "credits" => {
      "label" => "Credits",
      "icon" => "sparkles",
      "plan_line" => "%{quantity} credits each period"
    }
  }

  config.usage_costs = {
    "ai.jev" => 1,
    "web.brave" => 5
  }
end
```

`RecordingStudioStripe.usage_cost("web.brave")` returns `5`. Keys must be strings. Values must be positive integers. An unknown key raises `ArgumentError` and does not return zero. A bad assignment raises at configuration time and leaves the previous map in place.

Included credits stay on the Price as `included_credits`. Two Prices on one Product can differ. A weekly Price can include 1,000 while the monthly Price includes 5,000. Plan cards read that through the meter plan line, so `included_credits` of 5000 with the plan line above reads "5k credits each period".

A credit pack is an allowance Price.

```text
meter = credits
allowance = 5000
```

`AllowanceCardComponent` renders that pack with the meter label, for example "+5k credits". Purchased credits keep the allowance Product's subscription type. A Pressbot pack does not add credits to Studio.

Spend with the line when the workspace can hold more than one plan.

```ruby
account.billing.line(:pressbot).spend_usage(
  key: "web.brave",
  quantity: 1,
  idempotency_key: "search:123"
)
```

`quantity` defaults to 1 and must be a positive integer. The credit amount is `quantity * rate`. That amount is what `meter(:credits).spend` records. For two Brave searches at 5 credits each, `quantity` on the usage row is 10, `usage_key` is `web.brave`, `source_quantity` is 2, and `credit_rate` is 5. The row keeps that rate if `usage_costs` later changes.

`usage_cost(key:, quantity:)` and `usage_available?(key:, quantity:)` compute the same credit amount and do not write a row. `usage_available?` calls `meter(:credits).available?`.

The balance is still the meter balance.

```text
remaining = included + purchased - usage
```

`included` is the current Price. `purchased` is allowance packs for that subscription type. `usage` is the credits already recorded in that subscription period. `spend_usage` does not calculate remaining on its own. A spend that does not fit raises `MeterLimitReached` and writes nothing. The same idempotency key returns the first row and does not spend again. The key is unique for the workspace root, not for each meter or subscription line. Give each billable operation its own key, such as a request id. Reusing a key across lines or events returns the original usage row.

`billing.spend_usage` uses the one live plan that holds included credits or a purchased credit pack. A plan with no included credits still counts when that line has purchased credits. It raises `AmbiguousSubscriptionLine` when more than one live plan holds credits. When more than one subscription type is configured and no live plan holds credits, it raises `SubscriptionLineRequired` and does not spend an untyped balance. With one subscription type, the unscoped meter fallback remains. `billing.meter(:credits)` still prefers the live plan with the larger included amount. Use `billing.line` for weighted spends whenever two groups can both hold credits. The usage row stores that line's `subscription_type`, and the period is that line's current period. `usage_key`, `source_quantity`, and `credit_rate` are only valid on the `credits` meter. Passing them to another meter raises `ArgumentError`.

`usage_cost` on `Billing` does not pick a plan. It only multiplies the tariff.

`credits_available?(minimum:)` and `record_credits(amount:, breakdown:, idempotency_key:)` sit on the same billing object and line as `spend_usage`. `minimum` and `amount` are positive integers. `credits_available?` compares `minimum` to remaining and does not write. `record_credits` writes the amount even when remaining is already 0. The breakdown Hash is stored on the usage row and is not priced again. The idempotency key is required. A repeat returns the first row. Recording Studio AI 0.21.0 can call these from `usage_precheck` and `usage_handler`. See the README section "Bill AI usage in credits".

The credits card on `/billing/usage` uses the same `FlatPack::Billing::UsageMeter` as the other meters. The line is usage of included plus purchased, such as `63 of 100`. Over that total, the line keeps the real usage (`150 of 100`) and the bar is danger. When that total is 0, the card says none on this plan and does not draw a bar.

Staff can open **Cents per credit** under the Stripe admin section. It divides each active credit price's amount by the credits that price grants, before tax and coupons. An annual plan divides by the credits included on that annual price. The cheapest price in a currency is marked. Other currencies are not part of that comparison.

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

The gem writes those rows on boot. Names come from this map only. DB-only paywalls are removed on boot. Then tick which paywalls a **Product** opens on New plan or Edit. Do not put them on a Price. Extra packs skip this.

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

A limit is a standing cap on the workspace right now. It is not a meter. Meters spend this Stripe period and reset. Limits do not reset when a period ends. Capacity comes back when current usage falls.

`aggregation` is `count`, `quantity`, or `per_item`. Omit it and the limit stays a count, which is the existing behaviour. `per_item` is opt-in. A host that does not configure one sees no change.

A **count** limit is how many live recordings of one type can exist. Example: 5 press kits. It requires `recordable_type`. `used` is `Recording.for_root(workspace).of_type("PressKit")` where `trashed_at` is nil. Nested recordings of that type share the cap. Trashed rows do not count.

A **quantity** limit is a current total, not a row count. Example: 5000000000 for storage. It does not need `recordable_type`. This gem does not know how the quantity is measured. The host, or another gem, registers that calculation. Register before anything reads `used`. A missing provider raises `ArgumentError` instead of pretending usage is 0. The block receives the workspace root recording and returns a non-negative integer.

```ruby
RecordingStudioStripe.configure do |config|
  config.limits = {
    "press_kits" => {
      "label" => "Press kits",
      "recordable_type" => "PressKit",
      "aggregation" => "count",
      "subscription_type" => "studio",
      "icon" => "rectangle-stack",
      "plan_line" => "%{quantity} press kits"
    },
    "storage_bytes" => {
      "label" => "Storage",
      "aggregation" => "quantity",
      "unit" => "bytes",
      "subscription_type" => "studio",
      "no_plan_limit" => 1.gigabyte
    },
    "max_file_bytes" => {
      "label" => "Max file size",
      "aggregation" => "per_item",
      "unit" => "bytes",
      "subscription_type" => "studio",
      "plan_line" => "Up to %{quantity} per file",
      "no_plan_limit" => 10.megabytes
    }
  }
end

RecordingStudioStripe.register_limit_usage(:storage_bytes) do |root_recording|
  MyStorageGem.current_bytes_for(root_recording)
end
```

`config.register_limit_usage` is the same registry. The number lives on the **Product** as `limit_<name>` metadata, for every kind, so monthly and yearly of the same plan share it. For count and quantity, missing or 0 means none on that plan. Admin New plan and Edit show one integer field per configured limit, including a per-item byte ceiling. Quantity limits stay plain integers. There is no separate meter on the plan card or on `/billing/usage`.

A **per-item** limit is a ceiling on one item, such as max file size. It does not need `recordable_type` or a usage reader. `ceiling` is the live plan's `limit_<name>`. The live plan is `Subscription.current_for` for that subscription type, so `past_due` still counts during grace. When the plan omits the key, `ceiling` is nil. nil means this gem is not capping the item. The consumer applies its own code max. Do not treat a missing key as 0. A workspace with no live plan, including a canceled plan, gets `no_plan_limit` when that positive integer is set, and nil when it is omitted. The same key is optional on count and quantity. With no live plan, `included` is that base instead of 0, and `used`, `remaining`, `available?`, `over?`, `with_capacity!`, and `enforce!` honor it. A live plan's `limit_<name>` always wins. Blank or 0 on that plan means none, with no fallback to the base. A non-positive or non-integer `no_plan_limit` raises `ArgumentError`. `unit` is `"bytes"` or omitted. `"bytes"` formats the number on every aggregation (plan cards, the usage meter, denials, and Gates). The Admin field stays a raw integer. Any other unit raises.

`allows?(amount)` is true when `ceiling` is nil or the positive integer `amount` is within the ceiling. `enforce_item!(amount)` raises `PlanLimitReached` when it is not, and it does not take an advisory lock. `used`, `remaining`, `over?`, `available?`, `enforce!`, and `with_capacity!` raise `ArgumentError` and point at `ceiling` and `enforce_item!`. `enforce_item!` on a count or quantity limit raises the same way. The Recording `before_create` count gate only runs for `count`. `/billing/usage` skips per-item limits, so it never asks them for `used` or `remaining`.

Plan cards show one line. With `unit: "bytes"` the default is `Up to 50 MB`. Without a unit it is `Up to 12`. `plan_line` can say `Up to %{quantity} per file`, and `%{quantity}` is already the formatted size. The line is never `x of y`. Gates lists the row as a Limit whose aggregation is "per item", and appends the no-plan base (`10 MB with no plan`) when one is set. Count and quantity rows do the same when `no_plan_limit` is set. The denial copy is "This file is larger than your plan allows. Upgrade for bigger uploads." HTML still redirects to `/plans`. JSON is still 403 `{ "code": "plan_limit_reached" }`.

```ruby
kits = account.billing.limit(:press_kits)
kits.included
kits.used
kits.remaining
kits.available?(1)
kits.over?

storage = account.billing.limit(:storage_bytes)
storage.included
storage.used
storage.remaining
storage.available?(12_000_000)
storage.over?
storage.enforce!(incoming_size)

files = account.billing.limit(:max_file_bytes)
files.ceiling
files.allows?(byte_size)
files.enforce_item!(byte_size)
```

`available?` takes a positive integer. The default is 1. Zero, a negative integer, a float, a string, or nil raises `ArgumentError`.

`line(:studio).limit(:press_kits)` is the same handle scoped to that group's live plan. Quantity limits use that same subscription type.

Prefer `with_capacity!` when the write should share the check. The block runs in a database transaction on the root recording. On Postgres the gem takes an advisory lock named for that root and that limit, and holds it until the transaction ends. Put the write that changes current usage inside the block, on that same connection, so the provider sees it and a second request waits.

```ruby
account.billing.limit(:storage_bytes).with_capacity!(incoming_size) do
  MyStorageGem.store!(account, incoming_size)
end
```

`enforce!` runs that same check under the same lock and returns true when the quantity fits. It raises `RecordingStudioStripe::PlanLimitReached` when it does not. The error carries the handle. If you call `enforce!` inside a transaction you already opened, the lock stays until you commit, and a write in that transaction is covered. If you call `enforce!` and write in a later transaction, another request can pass the check first. `enforce!` does not reserve capacity by itself. The write does.

The lock does not cover a write that leaves this database transaction: another process, a file store, or a job queued after the check. Non-Postgres adapters skip the advisory lock, the same way they do for count creates.

Creating another recording of a count-limited type is blocked at the Recording. `revise` does not consume a slot. Restore from trash does, because used ignores trashed rows. Moving a live row into a full workspace does too. The gate only runs when the destination root enabled `:stripe`, and only for limits whose aggregation is `count`. It checks `enforce!(1)`. A quantity limit is not inferred from a Recording create, restore, or move. A per-item limit is not inferred either. Call `enforce_item!` for one item. The gem that performs a quantity write calls `with_capacity!`. The gem raises `RecordingStudioStripe::PlanLimitReached`. HTML redirects to `/plans`, or `config.limit_reached_path`. JSON is 403 `{ "code": "plan_limit_reached" }`. Dummy copy: “Pick a plan to add press kits.” or “Starter includes 3 press kits. Upgrade, or archive one.” A quantity limit says “Upgrade, or free some up.” Recording Studio core still swallows `before_record` errors, so the count gate is `Recording` `before_create` (and restore, and move) until core can deny `record!`. `PlanLimitGuard` reaches `Recording` through the `:stripe` capability: `RecordingBilling` includes it, and core `apply_capabilities!` mixes that module in on each load. Core assigns `root_recording_id` before the guard runs.

Downgrades do not delete extras. `over?` is true and `available?` is false until current usage falls. For a count, that is an archive. For a quantity, that is the registered usage dropping. A per-item ceiling has no `used` total to clear. Accessible stays access. Do not `record` usage for these caps. A billing period does not clear them.

Dummy seeds Starter at 3 press kits and a 50 MB file ceiling, Pro at 10 and 2 GB, and Team at 25 press kits with no file key. A workspace with no live Studio plan is capped at 10 MB per file when `max_file_bytes` is configured. Inbox plans do not include press kits. `/billing/usage` shows the standing count and quantity caps as a progress bar and skips per-item ceilings. Dummy `/press_kits` is the product screen that lists kits and adds them. Plan cards on `/plans` and `/pricing` list those caps, included usage, and ticked features, with icons from the host config.

## Remaining

For that plan's subscription period:

```text
remaining = included + purchased - usage
```

Included comes from Price metadata. Purchased comes from allowance packs bought from the start of that period’s calendar month through period end. Usage is what the app recorded for that plan group. Postgres takes an advisory lock around spend, standing count creates, and `with_capacity!` / `enforce!`. Other databases skip the lock. Standing limits are not part of that period math.

## Plan changes

- Higher monthly amount: confirmation page first, then update the Stripe Subscription now, `proration_behavior: always_invoice`, `payment_behavior: error_if_incomplete`. Local Price waits for the webhook
- Lower monthly amount, default `downgrade_timing: at_period_end`: confirmation page first, then keep the current Price, store `scheduled_price`. Stripe gets a schedule created from the Subscription, then an update with every current item copied into both phases. An existing schedule is released first. A failed schedule does not change the live Price
- `downgrade_timing: immediately` on that plan group: the confirmation says the switch is today and unused time is credited. `ChangePlan` updates the Stripe Price now with `proration_behavior: create_prorations`. It does not create a schedule. The local Price still waits for the webhook
- Same Product, a longer interval is an upgrade: week, then month, then year. A shorter interval is a downgrade. Across Products, `rank` metadata wins. With no rank, compare a monthly equivalent (weekly amount × 52 / 12, yearly amount / 12)
- Cancel, default timing: confirmation page first, then `cancel_at_period_end` on that group's Subscription. Pass `subscription_type` when more than one live plan exists. Stay on this plan on billing clears a scheduled downgrade
- Cancel with `downgrade_timing: immediately`: the confirmation says the plan ends today. Stripe `Subscription.cancel` ends it now. The local row waits for `customer.subscription.deleted`
- When the webhook applies a different Product, or ends the Subscription, the gem emits `plan_downgraded.recording_studio_stripe` only if a paywall or a `limit_<name>` was lost. Count and quantity treat a missing or 0 key as none. A per-item key that is missing or blank is unlimited. Cancel uses `no_plan_limit` for every kind (nil is unlimited for per-item, and none for count and quantity). Dropping onto a lower base lists that limit. Nothing is deleted. New writes stay blocked while usage is over the base. The host handles that event. See the README Downgrades section
- Checkout for a group that already has a live plan opens the confirmation page. It does not apply the change, and it does not open a second Stripe Subscription. A first Checkout in an empty group reserves an incomplete local row so a second attempt cannot mint another Stripe Subscription

## Screens

Customer UI is a mountable engine slice at `/plans`, `/billing`, and `/billing/usage`. Dummy home is the host hub: Flatpack `SidebarLayout`, rounded theme. Dummy product screens use Flatpack's rounded theme. `/plans` is titled Pricing. The title, subtitle, and interval pills sit centered. A pill sits in week, month, year order, and only when that group has a Price for it. Group names (Studio, Inbox) only show when more than one type has Products; then each group keeps its own interval pills. One type puts the pills under the page title. Upgrade and Downgrade open `/billing/subscription/change`, which asks you to confirm the new price and when it takes effect. Confirm PATCHes the subscription. A host with one implied type still uses `?interval=year` or `?interval=week`. Several types use `?interval[studio]=year` or `?interval[studio]=week` so Inbox can stay monthly. Default view stays monthly. A local checkout on a weekly Price ends one week out. Month stays one month. Year stays one year. A trial still ends after its days. `RecordingStudioStripe::PlanIntervals` builds those hrefs. Close on those pages goes to the host home (`main_app.root_path`). The back chevron is browser history, so Close is the way out of the slice.

`/billing` is the money page: live plan cards and **Manage billing on Stripe** when the workspace has a Customer and the actor can `:admin`. **See usage** opens `/billing/usage` when a live plan has recorded standing-cap or meter use. It stays off when there is no plan, and when every cap and meter is still zero. The Stripe button uses the gem's `:stripe` Flatpack style. The paint is Stripe blurple. Hosts on Flatpack 0.1.189 or newer get `register_style`. The billing view loads `recording_studio_stripe/button` through `content_for :head`. If the host layout does not yield `:head`, link that stylesheet after Flatpack. Each live plan group gets its own `FlatPack::Billing::PlanSummary`. The plan name is the card heading. The price is its own line, such as `$29/month`. Renewal or trial timing is the next line: `Renews in 21 days`, `Renews in 1 day`, `Renews today`, `Trial ends in 2 days`, `Trial ends in 1 day`, or `Trial ends today`. Past due and a plan that ends this period omit that timing line. The status badge is the one PlanSummary draws: Active, Trial, Past due, or Canceled. A past due plan also shows the past-due status alert. A trial that ends within 7 days shows the trial-ending status alert. A canceled plan shows the canceled status alert. Canceling at period end is still an active plan: an Ends this period badge sits with the actions, an alert names the end date, and Keep this plan is a submit in that row. A scheduled change stays on the active badge, with a Change scheduled badge, an alert naming the next plan, and Stay on this plan. When more than one subscription type is configured, the group name (Studio, Inbox) is muted text above the summary. PlanSummary's footer slot does not emit its content in Flatpack 0.1.356, so those pieces are not inside the card footer. Over a cap, or within 15% of one, the plan card shows a status alert with a custom title. The usage meter does not. The page subtitle still names the calendar date for a trial. Extra packs stay off this page. Hosts that still sell them can render `AllowanceCardComponent` and POST `allowances`. `/billing?checkout=ok` explains the wait when Stripe has not written the subscription yet. Money actions use `stripe_action_form`: one form, one Flatpack submit. Portal and checkout forms set `data-turbo="false"`. Manage billing POSTs a Stripe Billing Portal session and redirects there. The return URL is the billing page (`success_path`). `:view` can read `/billing` and `/billing/usage` and cannot open the portal. `:edit` cannot pay. Hosts turn the portal on in the Stripe Dashboard. Do not link to dashboard.stripe.com. Do not copy invoices or cards into local tables.

`/billing/usage` shows standing caps and period meters, one full-width card per metric. A workspace with no live plan still shows a meter when a count or quantity limit has `no_plan_limit`, or recorded usage. `unit: "bytes"` prints those numbers as sizes, such as `1 GB of 2 GB`. Caps sit with that group's meters, not on the plan card. There is no group heading (Studio usage stays off). Each cap and each meter is `FlatPack::Billing::UsageMeter`. The line reads usage of the cap. `display` is `count` (the default), such as `2 of 10` or `1 GB of 2 GB`, or `percent`, such as `75%`. The old `used/included` line is gone. The bar warns at 80% and turns danger at the cap. A zero limit is UsageMeter `limit: 0`, which reads `None on plan` and draws no bar. That is not Unlimited. A workspace with no live plan does not see "this plan" on `PlanLimitReached`. Set `action` to `upgrade` or `purchase` when that card should show a button. `upgrade` opens the plans page. `purchase` needs `action_url`. `action_label` replaces the button text. `action_method` of `post`, `put`, `patch`, or `delete` submits a form. Anything else is a link. Omit `action` and the card stays text only. The button shows when the bar is warning or danger, and on a zero cap. A nil cap is Unlimited (`4 · Unlimited`, no bar). Count and quantity caps from this gem are never nil: a missing number is 0, which means none. This page still skips per-item ceilings, including an unlimited per-item ceiling. The usage card does not show a near-limit or over-limit status alert. The bar carries that. UsageMeter has no included/purchased breakdown, so a meter that mixes plan include and extra packs adds that split as the meter's description, such as `10m on this plan. 5m from extra packs.` The **Breakdown** dropdown is gone. The meter total stays included plus purchased. `AllowanceCardComponent` is still the pack checkout button. It has no used amount and no cap, so it does not render a meter. Purchased packs change the meter on this page. HTML `MeterLimitReached` redirects here, or to `config.usage_path`. `RecordingStudioStripe::UsageComponent` is the reusable block. Pass `billing:` and optional `lines:`. Dummy's Usage sidebar item is this page.

`RecordingStudioStripe::PlansComponent` is the reusable pricing block. Pass `groups:` from `Catalog.plan_groups` when types are configured, with each group's own interval hrefs from `PlanIntervals`. Default `align: :center` centers the title, subtitle, and interval pills. Each pill shows only when that group has a Price for it. `stripe_plan_intervals` returns that list. Pass `intervals:` to limit it. A requested interval missing from that list uses the first interval that has a Price. Pass `align: :left` if the host screen needs that. Dummy `/plans` and `/pricing` are both centered. Dummy `/pricing` does not require a login. Default `density: :auto` draws a compact row on a phone and the tall card from the `md` breakpoint. On a phone the name is one line, the marketing subtitle hides, the price is smaller, and the features sit behind What’s included. From `md` the name, the price, the button, and the feature list are four subgrid rows, so they line up across the cards. The grid is one column on a phone, two from `md`, and three from `lg`. `density: :cards` keeps the tall card at every width, including a phone, and still uses that grid. `density: :rows` keeps the compact row at every width and stacks the plans with `FlatPack::Collection` (`as: :list`, `layout: :stack`, `gap: :sm`). `PlanCardComponent` defaults to `density: :cards`. Pass the same `density:` when a host renders that card in its own row. An unknown density raises `ArgumentError`. `config.layout` chooses the engine chrome. It does not set plan density. Each card is a Flatpack list of caps, included usage, ticked features, and any extra lines on that Product. The page heading and each group heading use `fp-on-backdrop`. FlatPack 0.1.327 paints that text from the backdrop tokens only when the layout has a background image. The title uses the backdrop content color. The subtitle uses the muted backdrop color. Cards sit outside that class and keep their surface text. A page with no background image keeps the normal surface colors. Staff use Recording Studio Admin. The gem registers one `:stripe` section with screens for Products, Prices, Gates, Meters, Paywalls, Customers, and Subscriptions. Gates is a catalog of every declared paywall, limit, and meter. Each row shows kind, key, label, count/quantity for limits, and which Products use it. **No plan** means none do. Quantity limits with no `register_limit_usage` block show **No usage reader** on the aggregation cell. Mutation forms (new plan, Price, and edit plan) live on the billing engine and link from those screens. Meters and Paywalls are name lists. Plan numbers stay on Product ticks, Product `limit_*` fields, and Price `included_*` fields. Edit names the plan, groups features with caps, and tucks pricing-card lines into a disclosure. Paid trial is its own section on new and edit plan. Dummy's Admin button switches onto the Studio Admin root first. Set `config.site_admin_recording` to that root, the admin root recordable, or a callable that returns one of those. A zero-argument callable runs with `instance_exec` on the controller. A callable may take `controller` or `controller:`. Stripe Admin forms authorize against that workspace only. If the setting is missing or returns nothing, those forms deny. They do not pick the first `stripe_admin` row. User billing screens still use `config.current_root_recording`.

## Local mode

Local mode is development or test with no Stripe secret key and no client. In that mode, Checkout writes a local Customer and Subscription (or allowance purchase) and returns the success URL. A trial checkout writes `trialing` and a period end of now plus the trial days. That local save emits `trial_started.recording_studio_stripe` once, after commit. Dummy uses this so you can click through without Stripe keys. Unsigned webhook JSON is accepted only in local mode, and only when `STRIPE_WEBHOOK_SECRET` is blank. A Stripe key or client with no webhook secret is rejected in every environment, including development. A missing or invalid signature returns 400. Production raises `RecordingStudioStripe::MissingWebhookSecret` on boot when `STRIPE_WEBHOOK_SECRET` is blank. `assets:precompile`, `assets:clean`, `assets:clobber`, and a boot with `SECRET_KEY_BASE_DUMMY` do not raise. A missing key outside development and test is not local mode, so production does not write local Checkout rows. Checkout `success_url` and `cancel_url` rebuild from the request scheme, host, and port plus `config.success_path` and `config.cancel_path`. Those paths must be site-relative. When Stripe is configured, `STRIPE_WEBHOOK_SECRET` is required. Production requires it even when Stripe is not configured. A handler that cannot apply yet returns 503 and leaves the event unstored so Stripe can retry. Webhook rows store the event id, type, created time, object id, and livemode. They do not store the full Stripe object. `invoice.paid` also stores `amount_paid`, `currency`, the invoice id, the Stripe customer and subscription ids, line price ids and amounts, and whether the invoice is a trial fee. Subscription events store `subscription_status`.

`invoice.paid` emits `invoice_paid.recording_studio_stripe` after commit for any Subscription status when `amount_paid` is greater than 0 and the invoice is not a trial fee. The payload includes `billing_reason` and `subscription_status`. A `canceled` status is not a conversion signal. A zero amount (free trial or a 100% coupon) does not emit. A trial fee is a line whose local Price has `kind=trial_fee` (any casing), with no other positive-amount line. A positive line with no price id is not a trial fee. A zero amount skips the Price check. A positive invoice for a local Subscription whose Price is not in the catalogue yet keeps the `past_due` to `active` change, stores `prices_pending`, and emits on replay or the pending sweep after the Price syncs. A later invoice waits with an older pending one until `config.prices_pending_max_hold` (default 3 days). After that, the later invoice can be `first_payment: true`, and the older one replays with `first_payment: false` if its Price syncs. `config.prices_pending_alert_after` (default 1 day) reports a still-missing Price once. `PricesPending.release!(webhook)` clears the flag without emitting. Replaying that webhook while the Price is still missing marks it pending again. An invoice with no Stripe subscription id returns 200 and emits nothing. An unknown Stripe subscription id returns 503. `first_payment` is true for a positive `subscription_create` with no earlier `invoice_paid` row, or for the next positive invoice only when `payments_tracked` is set. The migration sets that flag on `trialing` and `incomplete` Subscriptions so a trial can convert to a first payment. The migration does not set the flag for `incomplete_expired`, `active`, `past_due`, `unpaid`, `paused`, or `canceled`, so the next invoice on those rows is `first_payment: false`. Reusing a local row for a new Stripe Subscription does not report first again. `invoice.paid` still sets a `past_due` Subscription back to `active`. Replay a stored webhook with `RecordingStudioStripe::ProcessWebhook.replay`. Replay reads the snapshot on that row and does not call Stripe. See the README for the payload, the publish lease, and the pending-publish sweep.

Hosts that do not use `current_user` set `config.current_actor`. Hosts that do not use `current_root_recording` set `config.current_root_recording`. Hosts that mount Stripe Admin forms set `config.site_admin_recording`. `draw_recording_studio_stripe at:` overwrites `config.mount_path`. Usage then lives at `{mount_path}/usage` unless you set `config.usage_path`. Billing controllers include `RecordingStudioAccessible::ControllerAuth` for actor/root. Money actions authorize through Accessible. Missing Accessible forbids those actions and Stripe Admin forms, and hides Manage billing on Stripe.

Recurring Checkout sessions send a new idempotency key each attempt. One-time pack Checkout does the same. Promotion codes are on. Set `config.automatic_tax = true` after Stripe Tax is on in the Dashboard. Checkout then also asks Stripe for the customer address.

Manage billing on Stripe still shows after a local checkout so hosts can see the control. The POST does not call Stripe. It redirects back to `/billing` with a flash.

## What this gem does not do

Stripe keeps invoices, cards, tax, and proration. This gem does not wrap other processors, invent wallets, or use Stripe Entitlements as a second catalogue. Plan features are paywall rows ticked on the Product. Do not copy invoices or payment methods locally.
