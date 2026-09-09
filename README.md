# Recording Studio Stripe

Stripe billing for Recording Studio roots. Stripe owns money. This gem owns the Rails layer that lets a workspace decide quickly:

```ruby
account.billing.line(:studio).meter(:ai_tokens).remaining
account.billing.limit(:press_kits).available?(1)
account.billing.unlocked?(:export_csv)
```

Meters spend this Stripe period (`included + purchased - usage`). Limits count how many of a type exist under the workspace (not trashed). Omit `config.subscription_types` and `account.billing.meter(:ai_tokens)` still talks to the one live plan.

This is a Stripe gem. It does not wrap other processors, invent wallets, or calculate tax. Turn Stripe Tax on in the Dashboard if you charge in the US or EU.

## What you get

- Stripe Products and Prices, including monthly and annual
- Optional plan groups (`config.subscription_types`) so one workspace can hold more than one live plan on the same Customer
- Checkout for a Customer
- Upgrade now with Stripe proration, after a confirmation of the new price
- Downgrade at the next renewal, after the same confirmation page
- Cancel at period end
- Included usage on a Price (`included_ai_tokens`, `included_api_calls` metadata)
- Standing inventory limits on a Product (`limit_press_kits` metadata) for how many of a type can exist
- Extra packs as one-time Prices (`meter`, `allowance` metadata)
- Customer plans page and billing page
- Manage billing on Stripe on `/billing` opens the Stripe Customer Portal for invoices and cards
- `PlansComponent` for those cards on a public page (`align: :center`) or a billing page (`align: :left`). Cards in a group share height, with the action in the footer
- Recording Studio Admin section for Products, Prices, Meters, Paywalls, Customers, and Subscriptions
- Named paywalls on a Product, checked with Accessible `authorized_action?`
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

Turn on the Customer Portal in the Stripe Dashboard. Manage billing on Stripe mints a portal session for the workspace Customer and sends the browser to Stripe. The gem does not copy invoices or cards. Leave keys blank in dummy and the button still shows after a local checkout, then flashes instead of calling Stripe.

Render the same plan cards on a host screen. Pass `groups:` from `Catalog.plan_groups` when you sell more than one kind of plan:

```erb
<% intervals = RecordingStudioStripe::PlanIntervals.from(params) %>
<%= render RecordingStudioStripe::PlansComponent.new(
  groups: RecordingStudioStripe::Catalog.plan_groups.map { |group|
    key = group[:key]
    group.merge(
      subscription: account.billing.line(key).subscription,
      **intervals.hrefs_for(key) { |query| plans_path(**query) }
    )
  },
  align: :left
) %>
```

A single-type host can still pass `products:`, `subscription:`, and one pair of monthly/yearly hrefs. Use `align: :center` on a public pricing page. Use `align: :left` on a signed-in billing page. Copy inside each card stays left either way.

Set `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, and `STRIPE_WEBHOOK_SECRET`. Leave them blank in dummy to click through locally.

Named usage counters default to `ai_tokens` and `api_calls`. Change `config.meters` in the initializer to add your own, then set `included_<name>` on each plan Price. Optional `icon` and `plan_line` on meters, paywalls, and limits are the words and icons on the public plan card.

To sell two plans at once, name the groups:

```ruby
RecordingStudioStripe.configure do |config|
  config.subscription_types = {
    "studio" => { "label" => "Studio" },
    "inbox" => { "label" => "Inbox" }
  }
end
```

Each plan Product belongs to one group. A workspace holds one live Stripe Subscription per group, still one Customer. `account.billing.line(:studio).subscription` is that group's plan. `account.billing.unlocked?(:export_csv)` is true if any live plan opens it. Use `billing.line(:inbox).unlocked?(:export_csv)` when the feature belongs to one group.

A `past_due` plan still counts as subscribed. Paywalls stay open and standing caps stay on that plan until Stripe marks it canceled. That is the grace period.

`account.billing.meter(:ai_tokens)` uses the live plan that includes that meter. Prefer `account.billing.line(:studio).meter(:ai_tokens)` when two plans both include it. New usage rows store that plan group. Call `spend` when the work must not run over the included amount. `record` still writes the fact after the work happened, even if that puts usage over remaining.

Pay, change plan, cancel, resume, extra packs, and Manage billing on Stripe need Accessible `:admin` on the workspace. `:view` can still read `/plans` and `/billing`. `:edit` cannot charge the workspace.

Named plan features live in `config.paywalls`. The gem writes those rows on boot. Staff tick which paywalls a Product opens. Monthly and yearly Prices on the same Product share them. Extra packs do not. Then:

```ruby
RecordingStudioAccessible.authorized_action?(
  actor: current_user,
  action: :generate_image,
  recording: current_root_recording
)
```

That is true when the actor has `:view` on the workspace root **and** a live plan Product includes that paywall. Meter spend stays `available?` before the work, or `spend` to check and write in one call. `record` logs usage that already happened. Buying Pro does not grant `:admin`.

Standing caps live in `config.limits`. The number sits on the Product, so monthly and yearly of the same plan share it. Missing or 0 means none on that plan. Creating another of that type, restoring it from trash, or moving it into a full workspace raises `RecordingStudioStripe::PlanLimitReached` (HTML redirects to `/plans`, or `config.limit_reached_path`; JSON is 403). The gate only runs under a root that enabled `:stripe`. Downgrades do not delete extras; `over?` is true until they archive. `used` counts every live recording of that type under the workspace, including nested ones.

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

kits = account.billing.limit(:press_kits)
kits.included
kits.used
kits.remaining
kits.available?(1)
kits.over?

tokens = account.billing.line(:studio).meter(:ai_tokens)
tokens.spend(1) if tokens.available?(1)
```

Omit `subscription_type` and the gem uses a matching plan group name if one exists, otherwise the first group. Do not give a limit the same name as a plan group unless they are meant to share it. Dummy Starter includes 3 press kits, Pro includes 10, and Team includes 25. Plan cards list those caps, included usage, and ticked paywalls. Hide, reorder, or add a display-only line on the Product with `plan_card` metadata. That hash stays local. Staff edit that on the plan form under Pricing card.

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

One Product per plan. Monthly and annual are Prices on that Product. Extra packs are a separate Product. `/plans` groups by Product, then by plan group when `config.subscription_types` is set. Admin Prices shows the Product name and filters by Product or interval.

Plan Products also store standing limits:

```text
limit_press_kits=3
```

Set those in Admin on the Product, not on each Price. Admin Prices has Edit for included usage. Stripe still owns the amount.

## Webhooks

Point Stripe at `POST /webhooks/stripe`. Set `STRIPE_WEBHOOK_SECRET` whenever Stripe keys are set. Unsigned JSON is only accepted in local mode. Do not deploy local mode on a public host. The gem then projects:

- `checkout.session.completed` and `checkout.session.async_payment_succeeded` for paid plans and extra packs
- `customer.subscription.*`
- `invoice.paid` and `invoice.payment_failed`
- `product.*` and `price.*`

`checkout.session.completed` does nothing until `payment_status` is `paid` or `no_payment_required`. A handler that cannot apply yet (Price or workspace missing) returns 503 and does not store the event, so Stripe retries. Checkout return still does not fulfil on its own. `/billing?checkout=ok` tells people to refresh if the subscription webhook has not landed. Choosing a plan in a group you already have opens a confirmation page, then upgrades or schedules a downgrade. It does not open a second Stripe Subscription. Stripe upgrades wait for the webhook before the local Price changes.

Set `config.automatic_tax = true` only after Stripe Tax is on in the Dashboard. Checkout then also sends `customer_update: { address: "auto" }`. Promotion codes are on by default.

Hosts that do not use `current_user` should set `config.current_actor`. Hosts that do not use `current_root_recording` should set `config.current_root_recording`. `draw_recording_studio_stripe at:` overwrites `config.mount_path`.

Recording Studio core still swallows `before_record` errors. Standing caps gate on `Recording` `before_create`, restore, and move until core can deny `record!` itself.

## Dummy

`test/dummy` is a host, not the product. Sign in at `/users/sign_in` with `admin@admin.com` / `Password`. Open `/plans` for left-aligned billing cards and `/pricing` for the centered public layout. Dummy seeds Studio (Starter, Pro, Team) and Inbox (Inbox, Inbox Plus, Inbox Pro) so one workspace can hold two live plans. Cards sort cheapest first and list caps, included usage, and ticked features. Home is the workspace. `/billing` shows the press kit cap with meters. `/press_kits` is where you add them; Starter caps them at 3. Admin is `/admin`.
