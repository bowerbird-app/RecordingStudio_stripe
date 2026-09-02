# Recording Studio Stripe

Stripe billing for Recording Studio roots. Stripe owns money. This gem owns the Rails layer that lets a workspace decide quickly:

```ruby
account.billing.meter(:ai_tokens).record(100_000)
account.billing.meter(:ai_tokens).remaining
account.billing.meter(:ai_tokens).available?(100_000)
```

`remaining` is included allowance plus purchased allowance minus usage, for the current Stripe period.

This is a Stripe gem. It does not wrap other processors, invent wallets, or calculate tax. Turn Stripe Tax on in the Dashboard if you charge in the US or EU.

## What you get

- Stripe Products and Prices, including monthly and annual
- Checkout for a Customer
- Upgrade now with Stripe proration
- Downgrade at the next renewal
- Cancel at period end
- Included usage on a Price (`included_ai_tokens`, `included_api_calls` metadata)
- Extra packs as one-time Prices (`meter`, `allowance` metadata)
- Customer plans page and billing page
- Recording Studio Admin section for Products, Prices, Meters, Customers, and Subscriptions
- Stripe webhooks that keep the local projection honest

## Install

```ruby
# Gemfile
gem "recording_studio_stripe", github: "bowerbird-app/RecordingStudio_stripe"
```

```bash
bin/rails generate recording_studio_stripe:install
bin/rails generate recording_studio_stripe:migrations
bin/rails db:migrate
```

Include billing on the workspace root:

```ruby
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", root: true
  include RecordingStudioStripe::Billable
end
```

Routes from the install generator:

```ruby
draw_recording_studio_stripe
```

That mounts billing at `/billing`, plans at `/plans`, and webhooks at `/webhooks/stripe`.

Set `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, and `STRIPE_WEBHOOK_SECRET`. Leave them blank in dummy to click through locally.

Named usage counters default to `ai_tokens` and `api_calls`. Change `config.meters` in the initializer to add your own, then set `included_<name>` on each plan Price.

### Admin

Install Recording Studio Admin and Accessible. Include `RecordingStudioStripe::AdminSupport` on the admin root. Enable the `:stripe` section. Grant Accessible access on that root. Mount Accessible under the admin path:

```ruby
mount RecordingStudioAccessible::Engine, at: "/admin/access"
recording_studio_admin_for :admin, at: "/admin", root_section: :stripe
```

Do not invent a second admin.

## Price metadata

Plan Prices:

```text
included_ai_tokens=10000000
included_api_calls=100000
```

Allowance Prices (one-time):

```text
kind=allowance on the Product
meter=ai_tokens
allowance=5000000
```

One Product per plan. Monthly and annual are Prices on that Product. Extra packs are a separate Product. `/plans` groups by Product and toggles interval. Admin Prices shows the Product name and filters by Product or interval.

## Webhooks

Point Stripe at `POST /webhooks/stripe`. The gem verifies the signature when `STRIPE_WEBHOOK_SECRET` is set, then projects:

- `checkout.session.completed` for extra packs
- `customer.subscription.*`
- `product.*` and `price.*`

Checkout return URLs do not fulfil anything. Stripe events do.

## Dummy

`test/dummy` is a host, not the product. Sign in at `/users/sign_in` with `admin@admin.com` / `Password`. Open `/plans` and `/billing`. Admin is `/admin`.
