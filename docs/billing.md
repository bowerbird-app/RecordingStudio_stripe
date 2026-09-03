# How billing works

Stripe is the source of truth for Products, Prices, Customers, Subscriptions, invoices, and cards. This gem keeps a thin local projection so a workspace can answer usage questions without a Stripe round trip.

## Data

| Thing | Where it lives |
| --- | --- |
| Product, Price | Stripe, copied into `recording_studio_stripe_products` / `_prices` |
| Customer | Stripe Customer id on the workspace root |
| Subscription | Stripe Subscription, plus a local status and period |
| Meter | Local named counter (`ai_tokens`, `api_calls`) |
| Usage | Append-only `recording_studio_stripe_usage_entries` |
| Extra packs | `recording_studio_stripe_allowance_purchases` after Checkout |
| Invoices, cards | Stripe Customer Portal. Not copied locally |
| Paywall | Local named feature (`generate_image`). Staff tick them on a plan Product |

Usage is a fact table, not a Recording. High volume stays off the tree. Paywalls are not Recordings either.

## Products and Prices

Stripe's shape is the shape here. A **Product** is the plan or pack. A **Price** is one way to pay for it.

Starter is one Product. Monthly and yearly are two Prices on that Product. Extra token packs are a separate Product with one-time Prices.

`/plans` groups by Product. A Monthly / Yearly toggle picks which Price each card shows. Admin Products is one row per Product, with Add Price. Admin Prices lists every Price with the Product name, and filters by Product or interval.

Choose plan and extra packs submit without Turbo so the browser can follow Stripe’s hosted Checkout URL. Turbo fetch cannot follow `checkout.stripe.com`.

Included usage lives on the Price, not the Product. Two Prices on Starter can include different amounts, though dummy uses the same numbers for month and year. Paywalls live on the Product, so monthly and yearly Pro share the same features.

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

The gem registers each paywall as an Accessible named action. The policy is `:view` on the recording **and** the current plan Product includes that paywall:

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

For the current subscription period:

```text
remaining = included + purchased - usage
```

Included comes from Price metadata. Purchased comes from allowance packs bought in the same period. Usage is what the app recorded.

## Plan changes

- Higher monthly amount: update the Subscription now, `proration_behavior: always_invoice`
- Lower monthly amount: keep the current Price, store `scheduled_price`, Stripe Subscription Schedule when keys are set
- Cancel: `cancel_at_period_end`

## Screens

Customer UI is a mountable engine slice at `/plans` and `/billing`. Dummy product screens use Flatpack's rounded theme. `/plans` switches monthly and yearly with pill buttons, not a joined segmented control.

`/billing` shows **Manage billing on Stripe** above the plan card when the workspace has a Customer and the actor can `:edit`. The current plan sits in a two-column grid so it does not stretch on a wide screen. The Active badge sits above the plan name. Usage cards show percent used this period. That POST creates a Stripe Billing Portal session and redirects there. The return URL is the billing page (`success_path`). `:view` can read `/billing` and cannot open the portal. Hosts turn the portal on in the Stripe Dashboard. Do not link to dashboard.stripe.com. Do not copy invoices or cards into local tables.

`RecordingStudioStripe::PlansComponent` is the reusable plans block. Pass `align: :left` on a signed-in billing page and `align: :center` on a public pricing page. Dummy `/plans` is left. Dummy `/pricing` is centered and does not require a login. Staff use Recording Studio Admin. The gem registers one `:stripe` section with screens for Products, Prices, Meters, Paywalls, Customers, and Subscriptions. Mutation forms (new Product, Price, Meter, Paywall, and edit Product) live on the billing engine and link from those screens. Dummy's Admin button switches onto the Studio Admin root first. Admin authorizes against that root, not the workspace you were billing.

## Local mode

When `STRIPE_SECRET_KEY` (or `Stripe_secret_key`) is blank, Checkout writes a local Customer and Subscription (or allowance purchase) and returns the success URL. Dummy uses this so you can click through without Stripe keys. Webhooks still accept unsigned JSON events when `STRIPE_WEBHOOK_SECRET` is blank.

Manage billing on Stripe still shows after a local checkout so hosts can see the control. The POST does not call Stripe. It redirects back to `/billing` with a flash.

When a test-mode secret is set, dummy `SeedDemoCatalog` creates (or reuses) Stripe Products and Prices tagged `recording_studio_demo`. Local `prod_local_` / `price_local_` ids are replaced so `/plans` Checkout can use the sandbox. Canonical env names win if both are set.

## Sandbox tests

`test/dummy/test/integration/stripe_sandbox_test.rb` talks to Stripe when `STRIPE_SECRET_KEY` or `Stripe_secret_key` is a test-mode key (`sk_test_` or `rk_test_`). GitHub CI has no keys, so that file skips. Set `STRIPE_SANDBOX_TEST=0` to skip it locally. It refuses live keys. The rest of the dummy suite stays in local mode even if the process has secrets.

## What this gem does not do

Stripe keeps invoices, cards, tax, and proration. This gem does not wrap other processors, invent wallets, or use Stripe Entitlements as a second catalogue. Plan features are paywall rows ticked on the Product. Do not copy invoices or payment methods locally.
