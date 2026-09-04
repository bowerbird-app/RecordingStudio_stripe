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

Usage is a fact table, not a Recording. High volume stays off the tree. Paywalls are not Recordings either.

## Products and Prices

Stripe's shape is the shape here. A **Product** is the plan or pack. A **Price** is one way to pay for it.

Starter is one Product. Monthly and yearly are two Prices on that Product. Extra token packs are a separate Product with one-time Prices.

`/plans` groups by Product. A Monthly / Yearly toggle picks which Price each card shows. When the host sets `config.subscription_types`, `/plans` also sections those Products by group. Admin Products is one row per Product, with Add Price. Admin Prices lists every Price with the Product name, and filters by Product or interval.

Included usage lives on the Price, not the Product. Two Prices on Starter can include different amounts, though dummy uses the same numbers for month and year. Paywalls live on the Product, so monthly and yearly Pro share the same features.

## Plan groups

A workspace has one Stripe Customer. It can hold one live plan per named group.

```ruby
RecordingStudioStripe.configure do |config|
  config.subscription_types = {
    "press_kits" => { "label" => "Press kits" },
    "media_monitoring" => { "label" => "Media monitoring" }
  }
end
```

Omit that map and the gem keeps one implied group (`plan`) and one live plan, which is today's behaviour.

Each plan Product belongs to one group. Starter and Pro for kits share `press_kits`. Monitoring Products share `media_monitoring`. Checkout for an empty group adds a Stripe Subscription on the same Customer. A different Product in a group you already have upgrades now or downgrades at renewal. Cancel stops that group only. Manage billing on Stripe stays one button. Stripe shows every Subscription for the Customer.

```ruby
account.billing.line(:press_kits).subscription
account.billing.line(:press_kits).meter(:kits).remaining
account.billing.unlocked?(:export_csv)
account.billing.line(:press_kits).unlocked?(:export_csv)
```

Meters must go through a line when periods differ. `account.billing.subscription` is still the latest live plan. Dummy seeds Studio and Inbox so you can click both.

Existing rows get type `plan`. If you configure exactly one type, `AssignSubscriptionTypes` remaps `plan` to that key on boot. If you configure more than one, assign each Product in Admin.

## Meters

A meter is a named counter the host records against. Defaults are `ai_tokens` and `api_calls`. The host replaces or extends that map:

```ruby
RecordingStudioStripe.configure do |config|
  config.meters = {
    "ai_tokens" => { "label" => "AI tokens" },
    "api_calls" => { "label" => "API calls" },
    "seats" => { "label" => "Seats" }
  }
end
```

The gem writes those rows on boot. Staff can also add a meter in Admin. Then:

```ruby
account.billing.meter(:seats).record(1)
```

A plan Price nominates how many of each meter it includes with `included_<meter_name>` metadata. Zero or missing means that meter is not part of the plan. The New Price form shows one included field per meter. Allowance packs name a meter and a quantity on a one-time Price (`meter`, `allowance`).

## Paywalls

A paywall is a named feature the host checks before a job. Hosts register names only:

```ruby
RecordingStudioStripe.configure do |config|
  config.paywalls = {
    "generate_image" => { "label" => "Generate an image" },
    "export_csv" => { "label" => "Export CSV" }
  }
end
```

The gem writes those rows on boot. Staff can add more in Admin. Then tick which paywalls a **Product** opens on New Product or Edit Product. Do not put them on a Price. Extra packs skip this.

The gem registers each paywall as an Accessible named action. The policy is `:view` on the recording **and** a live plan Product includes that paywall:

```ruby
RecordingStudioAccessible.authorized_action?(
  actor: current_user,
  action: :generate_image,
  recording: current_root_recording
)
```

Meter spend stays `available?` / `record`. Buying a plan does not grant `:admin`. Paywalls are not Stripe Entitlements and not a `plan_id` on User.

Dummy registers `generate_image` and `export_csv`, and ticks `generate_image` on Pro only.

## Remaining

For that plan's subscription period:

```text
remaining = included + purchased - usage
```

Included comes from Price metadata. Purchased comes from allowance packs bought in the same period. Usage is what the app recorded.

## Plan changes

- Higher monthly amount: update the Subscription now, `proration_behavior: always_invoice`
- Lower monthly amount: keep the current Price, store `scheduled_price`, Stripe Subscription Schedule when keys are set
- Cancel: `cancel_at_period_end` on that group's Subscription

## Screens

Customer UI is a mountable engine slice at `/plans` and `/billing`. Dummy product screens use Flatpack's rounded theme. `/plans` puts monthly and yearly pills under each plan group name, left aligned, above that group's cards. A host with one implied type still uses `?interval=year`. Several types use `?interval[studio]=year` so Inbox can stay monthly. `RecordingStudioStripe::PlanIntervals` builds those hrefs.

`/billing` shows **Manage billing on Stripe** above the plan cards when the workspace has a Customer and the actor can `:edit`. Each live plan group gets its own card. Usage cards show percent used this period for that group's meters. That POST creates a Stripe Billing Portal session and redirects there. The return URL is the billing page (`success_path`). `:view` can read `/billing` and cannot open the portal. Hosts turn the portal on in the Stripe Dashboard. Do not link to dashboard.stripe.com. Do not copy invoices or cards into local tables.

`RecordingStudioStripe::PlansComponent` is the reusable plans block. Pass `groups:` from `Catalog.plan_groups` when types are configured, with each group's own interval hrefs from `PlanIntervals`. Pass `align: :left` on a signed-in billing page and `align: :center` on a public pricing page. Dummy `/plans` is left. Dummy `/pricing` is centered and does not require a login. Staff use Recording Studio Admin. The gem registers one `:stripe` section with screens for Products, Prices, Meters, Paywalls, Customers, and Subscriptions. Mutation forms (new Product, Price, Meter, Paywall, and edit Product) live on the billing engine and link from those screens. Dummy's Admin button switches onto the Studio Admin root first. Admin authorizes against that root, not the workspace you were billing.

## Local mode

When `STRIPE_SECRET_KEY` is blank, Checkout writes a local Customer and Subscription (or allowance purchase) and returns the success URL. Dummy uses this so you can click through without Stripe keys. Webhooks still accept unsigned JSON events when `STRIPE_WEBHOOK_SECRET` is blank.

Manage billing on Stripe still shows after a local checkout so hosts can see the control. The POST does not call Stripe. It redirects back to `/billing` with a flash.

## What this gem does not do

Stripe keeps invoices, cards, tax, and proration. This gem does not wrap other processors, invent wallets, or use Stripe Entitlements as a second catalogue. Plan features are paywall rows ticked on the Product. Do not copy invoices or payment methods locally.
