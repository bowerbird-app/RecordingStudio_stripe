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

Usage is a fact table, not a Recording. High volume stays off the tree.

## Products and Prices

Stripe's shape is the shape here. A **Product** is the plan or pack. A **Price** is one way to pay for it.

Starter is one Product. Monthly and yearly are two Prices on that Product. Extra token packs are a separate Product with one-time Prices.

`/plans` groups by Product. A Monthly / Yearly toggle picks which Price each card shows. Admin Products is one row per Product, with Add Price. Admin Prices lists every Price with the Product name, and filters by Product or interval.

Included usage lives on the Price, not the Product. Two Prices on Starter can include different amounts, though dummy uses the same numbers for month and year.

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

Customer UI is a mountable engine slice at `/plans` and `/billing`. Staff use Recording Studio Admin. The gem registers one `:stripe` section with screens for Products, Prices, Meters, Customers, and Subscriptions. Mutation forms (new Product, Price, Meter) live on the billing engine and link from those screens. Dummy's Admin button switches onto the Studio Admin root first. Admin authorizes against that root, not the workspace you were billing.

## Local mode

When `STRIPE_SECRET_KEY` is blank, Checkout writes a local Customer and Subscription (or allowance purchase) and returns the success URL. Dummy uses this so you can click through without Stripe keys. Webhooks still accept unsigned JSON events when `STRIPE_WEBHOOK_SECRET` is blank.

## What this gem does not do

Stripe keeps invoices, cards, tax, and proration. This gem does not wrap other processors, invent wallets, or score entitlements beyond `remaining`.
