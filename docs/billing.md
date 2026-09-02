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
