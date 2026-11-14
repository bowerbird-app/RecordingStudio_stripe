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
- Downgrade at the next renewal, after the same confirmation page. A plan group can set `downgrade_timing: :immediately` to switch the Stripe Price now, with proration
- Cancel at period end, after a confirmation that names the plan and the end date. That same `immediately` setting ends the subscription now
- Included usage on a Price (`included_ai_tokens`, `included_api_calls` metadata)
- Standing inventory limits on a Product (`limit_press_kits` metadata) for how many of a type can exist, plus an opt-in per-item ceiling (`limit_max_file_bytes`) for one file or one item
- Extra packs as one-time Prices (`meter`, `allowance` metadata)
- Optional paid or $0 trial on a plan Product (`trial_days`, `trial_unit_amount`, plus a one-time `kind=trial_fee` Price)
- Customer pricing page, billing page, and usage page
- Manage billing on Stripe on `/billing` opens the Stripe Customer Portal for invoices and cards
- Usage at `/billing/usage` for standing caps and period meters
- `PlansComponent` for those cards, centered by default (`align: :center`). Default `density: :auto` draws a compact row on a phone and, from the `md` breakpoint, four subgrid rows so the name, the price, the button, and the feature list line up. `density: :cards` keeps the tall card on a phone. `density: :rows` keeps the compact row at every width
- `UsageComponent` for caps and meters on a host screen
- Recording Studio Admin section for Products, Prices, Gates, Meters, Paywalls, Customers, and Subscriptions. Gates lists declared paywalls, limits, and meters. Meter and paywall names come from config. Product and Price screens still edit plan numbers
- Named paywalls on a Product, checked with Accessible `authorized_action?`
- Stripe webhooks that keep the local projection honest

## Install

```ruby
# Gemfile
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v6.7.0"
gem "recording_studio_stripe", github: "bowerbird-app/RecordingStudio_stripe"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.32.0"
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.360"
gem "view_component", "4.19.0"
```

This gem requires `recording_studio` `>= 6.5.0`, Accessible `>= 0.32.0, < 1.0`, `view_component` `>= 4.14, < 5`, and `flat_pack` `>= 0.1.360`. The pin above loads FlatPack `0.1.360`, which lets UsageMeter take `limit: 0` and lets Button submit a form with `url:`. Accessible `>= 0.32.0, < 1.0` no longer matches 0.24 through 0.31.

`config.layout` chooses the screen chrome for this engine. `nil` uses `RecordingStudio.configuration.layout`, then `"recording_studio/default_layout"`. A String is a layout name. `false` renders with no layout. A callable must take `controller:` and return a String, `nil`, or `false`.

```ruby
RecordingStudioStripe.configure do |config|
  config.layout = "billing"
end
```

Page titles are `content_for :title` and `content_for :subtitle`. The default layout draws one heading above the page. Back and close go through `flat_pack_page_nav`. Extra actions go through `register_page_nav` or `content_for :page_nav_right`. `/plans` centers its title and subtitle in `PlansComponent` and does not set `content_for :title`, so the layout does not draw a second heading. That heading and each group heading use `fp-on-backdrop`. FlatPack changes their color only when the layout has a background image. Plan cards sit outside the class and keep their surface text.

`recording_studio_background_image(url)` sets `content_for :background_image`. The default layout passes that URL to `FlatPack::PageLayout` as a decorative image (`alt=""`, `loading="lazy"`). A blank URL leaves the page unchanged. `/plans` passes `config.plans_background_image`. That setting defaults to nil. `recording_studio_page_width(:wide)` sets `content_for :page_width`. Allowed values are `:narrow`, `:default`, `:wide`, and `:full`. A blank value stays `:default`.

Checkout `success_url` and `cancel_url` are built from the request scheme, host, and port plus `config.success_path` and `config.cancel_path`. Those paths must be site-relative (`/billing`, not `//other.example`).

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

That mounts billing at `/billing`, usage at `/billing/usage`, pricing at `/plans`, and webhooks at `/webhooks/stripe`.

Turn on the Customer Portal in the Stripe Dashboard. Manage billing on Stripe mints a portal session for the workspace Customer and sends the browser to Stripe. The button uses the gem's `:stripe` Flatpack style. The gem does not copy invoices or cards. Leave keys blank in dummy and the button still shows after a local checkout, then flashes instead of calling Stripe.

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
  align: :center,
  density: :auto
) %>
```

A single-type host can still pass `products:`, `subscription:`, `weekly_href`, `monthly_href`, and `yearly_href`. `hrefs_for` already includes `weekly_href`. A pill shows only when that group has a Price for it. `stripe_plan_intervals(products)` returns those intervals. Pass `intervals:` to limit them, for example `%w[month year]`. When the requested interval is not in that list, the cards use the first interval that is. The card row keeps Products that have a Price for the interval on screen. `align: :center` is the default and centers the title, subtitle, and interval pills. Pass `align: :left` if the host screen needs that. Copy inside each card stays left either way. `density: :auto` is the default. On a phone each plan is a compact row. The name stays on one line, the marketing subtitle hides, the price is smaller, and the features sit behind What’s included. From the `md` breakpoint those cards share four subgrid rows again, and the feature list stays open. The grid is one column on a phone, two from `md`, and three from `lg`. Pass `density: :cards` to keep the tall card on a phone. Pass `density: :rows` to keep the compact row at every width. That stacks the plans in a list with a small gap. `PlanCardComponent` defaults to `density: :cards`. Pass `density:` when a host renders that card itself. `config.layout` is the engine layout. It does not choose density. An unknown density raises `ArgumentError`. Group titles such as Studio and Inbox only render when more than one type has Products. Week is `/wk` on the card. `?interval=week` and `?interval[studio]=week` select it. Default view stays monthly.

Set `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, and `STRIPE_WEBHOOK_SECRET`. Leave the keys blank in development or test to click through locally. Production will not boot without `STRIPE_WEBHOOK_SECRET`.

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

A `past_due` plan still counts as subscribed. Paywalls stay open and standing caps stay on that plan until Stripe marks it canceled. That is the grace period. Billing shows **Past due** and **Update card** so people can fix the card in Stripe.

`account.billing.meter(:ai_tokens)` uses the live plan that includes that meter. Prefer `account.billing.line(:studio).meter(:ai_tokens)` when two plans both include it. New usage rows store that plan group. Call `spend` when the work must not run over the included amount. `record` still writes the fact after the work happened, even if that puts usage over remaining.

A `credits` meter can price several operations without a separate quota for each one. Set `included_credits` on the plan Price. A one-time pack uses `meter` `credits` and `allowance` for the pack size. Remaining credits are the plan include, plus purchased packs, minus weighted usage.

```ruby
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
```

```ruby
account.billing.line(:pressbot).spend_usage(
  key: "web.brave",
  quantity: 1,
  idempotency_key: "search:123"
)
```

`spend_usage` multiplies the quantity by the configured rate and spends that many credits. The usage row stores the key, the source quantity, and the rate from that call. A later change to `usage_costs` does not rewrite the row. Those source fields belong on the `credits` meter. Passing them to another meter raises `ArgumentError`. `RecordingStudioStripe.usage_cost("web.brave")` returns the rate. `billing.line(:pressbot).usage_cost(key:, quantity:)` returns the credits that spend would use, and `usage_available?` checks the line without writing a row. When more than one live plan holds credits, call `billing.line`. `billing.spend_usage` raises `AmbiguousSubscriptionLine` in that case. When more than one subscription type is configured and no live plan holds credits, it raises `SubscriptionLineRequired`. The idempotency key is unique for the workspace, not for each line. Use a fresh request id for each operation. Reusing a key returns the original usage row.

### Bill AI usage in credits

[Recording Studio AI](https://github.com/bowerbird-app/RecordingStudio_AI) 0.21.0 prices each attempt and calls two host hooks. This gem does not know about that gem. Wire the hooks to the credits meter. `usage_precheck` runs before the provider call. `usage_handler` runs after it, with a whole positive `credits` integer. A failed attempt that reported usage is still charged. The same key must not charge twice.

```ruby
config.usage_precheck = lambda do |attribution:, minimum:|
  RecordingStudioStripe::Billing
    .for_recording(attribution.root_recording)
    .line(:pressbot)
    .credits_available?(minimum:)
end

config.usage_handler = lambda do |credits:, breakdown:, idempotency_key:, attribution:|
  RecordingStudioStripe::Billing
    .for_recording(attribution.root_recording)
    .line(:pressbot)
    .record_credits(amount: credits, breakdown:, idempotency_key:)
end
```

`credits_available?(minimum:)` is true when the credits meter's remaining is at least `minimum`. `minimum` is a whole integer of 1 or more. The compare does not coerce floats.

`record_credits` writes that many credits on the credits meter. It does not check the remaining balance, because the work already ran. It does not call Stripe. `amount` is a positive integer. `breakdown` is a Hash stored as JSON and is not read back for pricing. The serialized Hash must be 16KB or smaller, and keys are stored as strings. `idempotency_key` is required. Keys from Recording Studio AI look like `ai-attempt:<id>`, `ai-batch-item:<id>`, and `ai-hosted-agent-turn:<id>`. The usage row stores `usage_key` `ai`, the amount in `quantity`, and leaves `source_quantity` and `credit_rate` empty. A repeated key returns the first row and writes nothing. A repeat with a different amount returns that same row, logs a warning, and does not overwrite it. There is no actor check and no charge screen. Call `billing.line` when the workspace can hold more than one plan. `billing.record_credits` follows the same line rules as `billing.spend_usage`.

`/billing/usage` shows each meter and standing cap with `FlatPack::Billing::UsageMeter`. The line is usage of the cap, such as `63 of 100`. The bar warns at 80% and turns danger at the cap. Over the total, the line keeps the real usage (`150 of 100`). A cap of 0 is a muted line, not a bar and not Unlimited. A nil cap is Unlimited. Count and quantity caps use 0 for none. A meter that mixes plan include and extra packs names both in the meter's description. The pack checkout card does not draw a meter.

Admin Stripe has a read-only **Cents per credit** screen. For each active price that grants credits, cents per credit is the price amount divided by the credits on that price. A pack is a one-time allowance price with `meter` `credits`. A plan price uses `included_credits` for that billing period, so an annual price divides by its own included amount. The figure is before tax and coupons. A plan row says the whole price is treated as the credit price. Trial prices, `kind=trial_fee` prices, $0 prices, prices with no credits, and inactive prices are left out. The cheapest price in each currency is marked. Prices in different currencies are not compared.

Pay, change plan, cancel, resume, extra packs, and Manage billing on Stripe need Accessible `:admin` on the workspace. `:view` can still read `/plans`, `/billing`, and `/billing/usage`. `:edit` cannot charge the workspace.

Named plan features live in `config.paywalls`. The gem writes those rows on boot. Staff tick which paywalls a Product opens. Monthly and yearly Prices on the same Product share them. Extra packs do not. Then:

```ruby
RecordingStudioAccessible.authorized_action?(
  actor: current_user,
  action: :generate_image,
  recording: current_root_recording
)
```

That is true when the actor has `:view` on the workspace root **and** a live plan Product includes that paywall. Meter spend stays `available?` before the work, or `spend` to check and write in one call. `record` logs usage that already happened. Buying Pro does not grant `:admin`.

Standing caps live in `config.limits`. The number sits on the Product as `limit_<name>`, so monthly and yearly of the same plan share it. Missing or 0 means none on that plan. There is no billing-period reset. `aggregation` defaults to `count`.

A count limit is how many live recordings of `recordable_type` can exist under the workspace, including nested ones. Trashed rows do not count. Creating another, restoring one from trash, or moving one into a full workspace raises `RecordingStudioStripe::PlanLimitReached` (HTML redirects to `/plans`, or `config.limit_reached_path`; JSON is 403). That gate only runs under a root that enabled `:stripe`, and only for count limits. Downgrades do not delete extras; `over?` is true until they archive.

A quantity limit is a current total, such as stored bytes. Leave `recordable_type` off. Register how to read that total. This gem does not measure it, and a Recording create does not enforce it. Call `with_capacity!` around the write so the check and the write share one transaction and, on Postgres, one advisory lock for that root and limit. `enforce!` is the same check when you are already inside that transaction. A later separate write can still race.

A per-item limit is a ceiling on one item, such as the largest file a workspace can upload. Set `aggregation` to `"per_item"`. Leave `recordable_type` off. There is no usage reader. `ceiling` is the live plan's `limit_<name>` (`Subscription.current_for`, so a `past_due` plan still counts). When that plan omits the key, `ceiling` is nil. nil means this gem is not capping the item. The consumer applies its own code max. A workspace with no live plan, including a canceled plan, gets `no_plan_limit` when you set that positive integer, and nil when you do not. `allows?(amount)` is true when `ceiling` is nil or `amount` is within it. `enforce_item!` raises `PlanLimitReached` and does not take a lock. `used`, `remaining`, `over?`, `available?`, `enforce!`, and `with_capacity!` raise. The Recording create gate and `/billing/usage` skip per-item limits. Optional `unit: "bytes"` formats every aggregation as a size (`5 GB`, `Up to 50 MB`) on the plan card, the usage meter, the denial, and Gates. Any other `unit` raises. Omit `unit` and the card shows a plain number (`Up to 12`). `plan_line` still interpolates `%{quantity}` after that formatting.

`no_plan_limit` is optional on count and quantity too. It is a positive integer or nil. Limits without it keep none when there is no live plan. With it, `included` is that base, so `used`, `remaining`, `available?`, `over?`, `with_capacity!`, and `enforce!` honor it. A live plan's `limit_<name>` always wins. Blank or 0 on that plan still means none, with no fallback to the base. `/billing/usage` shows the meter for a no-plan workspace when that base, or recorded usage, is positive. A later downgrade under the base blocks new writes and deletes nothing. A workspace with no live plan never sees the words "this plan" on that alert or on `PlanLimitReached`.

Each limit can set `action` to `"upgrade"` or `"purchase"`. Omit it and the usage card stays text only. `upgrade` links to the plans page unless you set `action_url`. `purchase` needs `action_url`, a path or a callable. `action_label` replaces the button text (`Upgrade` or `Buy more`). `action_method` defaults to a link. `post`, `put`, `patch`, or `delete` submits a form. The button shows on a zero cap, a near-limit alert, and an over-limit alert.

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
      "no_plan_limit" => 1.gigabyte,
      "action" => "upgrade"
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

kits = account.billing.limit(:press_kits)
kits.included
kits.used
kits.remaining
kits.available?(1)
kits.over?

storage = account.billing.limit(:storage_bytes)
storage.with_capacity!(incoming_size) { MyStorageGem.store!(account, incoming_size) }

files = account.billing.limit(:max_file_bytes)
files.ceiling
files.enforce_item!(byte_size) if files.allows?(byte_size)

tokens = account.billing.line(:studio).meter(:ai_tokens)
tokens.spend(1) if tokens.available?(1)
```

Omit `subscription_type` and the gem uses a matching plan group name if one exists, otherwise the first group. Do not give a limit the same name as a plan group unless they are meant to share it. Dummy Starter includes 3 press kits, Pro includes 10, and Team includes 25. Plan cards list those caps, included usage, and ticked paywalls. Hide, reorder, or add a display-only line on the Product with `plan_card` metadata. That hash stays local. `subtitle` in that hash sits under the plan name. Staff edit it next to the name. The rest of the card controls sit under Pricing card. `product.card_subtitle` reads the line.

A plan can offer a trial. Set Trial days and Trial amount in cents on the Product in Admin, or call `AssignTrial`:

```ruby
RecordingStudioStripe::AssignTrial.call(product: pro, days: 14, unit_amount: 100)
pro.trial.offered? # true
pro.trial.checkout_label # "Try now"
pro.trial.duration_label # "14 day trial"
pro.trial.amount_label # "$1"
```

Checkout starts the real plan Price with Stripe `trial_period_days`. A one-time fee Price on the same Product (`kind=trial_fee`) is the charge now. 0 cents is a free trial on that same path. `Product#monthly_price` stays the paid monthly Price. Empty days clears the trial and deactivates fee Prices. A workspace that already has a live plan in that group still upgrades or downgrades. Dummy Pro is $1 for 14 days. On `/billing`, Trial uses the primary badge and the plan name is a FlatPack `h2`. The group name is muted text above the plan name. Trial and Current sit top-right. Relative timing sits in brackets after the price. `/plans` cards stay `h3`.

### Admin

Install Recording Studio Admin and Accessible. Include `RecordingStudioStripe::AdminSupport` on the admin root. Enable the `:stripe` section. Grant Accessible access on that root. Name that workspace on this gem. Mount Accessible under the admin path:

```ruby
RecordingStudioStripe.configure do |config|
  config.site_admin_recording = lambda {
    admin_root = AdminRoot.find_by(name: "Studio Admin")
    next unless admin_root

    RecordingStudio.root_recording_for(admin_root)
  }
end

mount RecordingStudioAccessible::Engine, at: "/admin/access"
recording_studio_admin_for :admin, at: "/admin", root_section: :stripe
```

`config.site_admin_recording` may be the root recording, the admin root recordable, or a callable that returns one of those. A zero-argument callable runs with `instance_exec` on the Stripe Admin controller (`self` is that controller), same as `config.current_actor`. A callable that takes `controller` or `controller:` receives the controller. `RecordingStudioStripe.site_admin_recording_for` is the public resolver. Stripe Admin forms authorize against that workspace only. If the setting is missing or returns nothing, those forms respond 403. They do not pick the first `stripe_admin` row. User billing screens still use `config.current_root_recording`.

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

Plan Products also store standing limits, count, quantity, or per item:

```text
limit_press_kits=3
limit_storage_bytes=5000000000
limit_max_file_bytes=2147483648
```

Set those in Admin on the Product, not on each Price. The field is a plain integer for each kind. A per-item value is the ceiling in the same unit you store (bytes, when `unit` is `"bytes"`). Admin Prices has Edit for included usage. Stripe still owns the amount.

## Downgrades

Each `config.subscription_types` entry takes an optional `downgrade_timing`.

- `at_period_end` is the default. A downgrade waits for the next renewal. A cancel keeps the plan until the period ends.
- `immediately` switches the Stripe Price on the current Subscription now. Stripe prorates a credit. A cancel ends that Subscription now.

Upgrades still charge the difference today. Unknown values raise `ArgumentError` when the host assigns `subscription_types`. Stripe remains the source of truth for the charge and for when the change is real.

The gem compares plans when a webhook moves the Subscription onto a different Product, or when Stripe ends it (`customer.subscription.updated` with status `canceled`, or `customer.subscription.deleted`, including after failed payments). The comparison uses the Product already stored locally, before that row is overwritten. A cancel compares with an empty plan. Paywalls on the old Product and not the new one are `paywalls_lost`. Count and quantity limits whose `limit_<name>` went down, or disappeared, are `limits_lowered`. Missing or 0 means none for those. A per-item limit uses the same rule as `LimitHandle#raw_ceiling`: a missing or blank `limit_<name>` is unlimited, not zero. A cap that becomes unlimited is not a loss. Unlimited that becomes a number is. On cancel, every kind compares with `no_plan_limit`. Nil there is unlimited for per-item, and none for count and quantity. The gem emits `plan_downgraded.recording_studio_stripe` only when something was lost or lowered. A higher Price that drops a count or quantity cap still emits, because the event is the loss. An upgrade or any other change that keeps every paywall and every limit emits nothing. Undoing a pending cancel or downgrade before it takes effect emits nothing.

`RecordingStudioStripe::DomainEvents::PLAN_DOWNGRADED` is that name. Schema version stays `1`. The row is written in the webhook transaction and published after commit. Delivery is at-least-once. The idempotency key is `plan_downgraded/` plus the Stripe event id, so a redelivery does not store a second row. `ProcessWebhook.replay` rebuilds that row from the webhook snapshot and does not call Stripe. A second replay does not notify again once the row is published.

The notification includes the usual `schema_version`, `id`, `occurred_at`, `subscription_id`, `customer_id`, and `root_recording_id`, plus:

- `subscription_type`
- `old_product_id` and `old_product_name` (local Product id and name)
- `new_product_id` and `new_product_name` (both nil when the plan was canceled)
- `paywalls_lost`
- `limits_lowered`, each with `name`, `from`, and `to`. For a per-item limit, nil means unlimited (`from: nil` is an uncapped plan that gained a ceiling). For a count or quantity limit, nil means the cap is gone (none). A set `no_plan_limit` is that `to` after a cancel
- `reason`, `downgrade` or `canceled`
- `timing`, `immediately` or `at_period_end` (`at_period_end` when a downgrade was already scheduled, or the cancel was already set for period end)
- `effective_at`, the Stripe event time in UTC

The payload has no Stripe SDK objects. `$0` invoices still do not emit `invoice_paid`.

```ruby
ActiveSupport::Notifications.subscribe("plan_downgraded.recording_studio_stripe") do |_name, _start, _finish, _id, payload|
  PlanCleanup.call(payload[:root_recording_id], payload[:paywalls_lost], payload[:limits_lowered])
end
```

Run the handler so a second delivery with the same `payload[:id]` does not do the work twice. The host decides what the loss means. This gem does not archive recordings or revoke anything else.

In local mode, an immediate downgrade or cancel updates the local Subscription directly and does not emit. There is no Stripe event to key.

## Webhooks

Point Stripe at `POST /webhooks/stripe`. Local mode is development or test with no Stripe secret key and no client. Unsigned JSON is accepted only in that mode, and only when `STRIPE_WEBHOOK_SECRET` is blank. A Stripe key or client with no webhook secret is rejected in every environment, including development. A missing or invalid signature returns 400. Production raises `RecordingStudioStripe::MissingWebhookSecret` on boot when `STRIPE_WEBHOOK_SECRET` is blank. `assets:precompile`, `assets:clean`, `assets:clobber`, and a boot with `SECRET_KEY_BASE_DUMMY` skip that raise so a build can compile files without the runtime secret. The gem then projects:

- `checkout.session.completed` and `checkout.session.async_payment_succeeded` for paid plans and extra packs
- `customer.subscription.*`
- `invoice.paid` and `invoice.payment_failed`
- `product.*` and `price.*`

`checkout.session.completed` does nothing until `payment_status` is `paid` or `no_payment_required`. A handler that cannot apply yet (Price or workspace missing) returns 503 and does not store the event, so Stripe retries. Checkout return still does not fulfil on its own. `/billing?checkout=ok` and `/billing?allowance=ok` tell people to refresh if Stripe is still writing. Choosing a plan in a group you already have opens a confirmation page, then upgrades or schedules a downgrade. It does not open a second Stripe Subscription. Stripe upgrades wait for the webhook before the local Price changes.

Webhook rows keep the event id, type, created time, object id, and livemode. They do not keep the full Stripe object. `invoice.paid` also keeps a small invoice snapshot: `amount_paid`, `currency`, `invoice_id`, `billing_reason`, the Stripe customer and subscription ids, each line's price id and amount (a line with no price id is kept), `lines_has_more`, and `trial_fee`. Subscription events keep `subscription_status`. A checkout event keeps that status when the session includes the subscription. If Checkout only has the subscription id, the gem retrieves the Subscription and stores that status too. Stripe sends the first 10 invoice lines. `lines_has_more` means a later page was not in the webhook.

## Domain events

After the database commit, the gem emits `ActiveSupport::Notifications`. Other gems can subscribe. This gem does not depend on them.

| Name | When |
| --- | --- |
| `trial_started.recording_studio_stripe` | The local Subscription is first saved as `trialing`, or first changes to `trialing`. Once per Subscription. |
| `invoice_paid.recording_studio_stripe` | `invoice.paid` with `amount_paid` greater than 0 that is not a trial fee. Status does not matter: trialing, active, past_due, and canceled all emit. |
| `plan_downgraded.recording_studio_stripe` | A webhook applied a different Product, or ended the Subscription, and a paywall or limit was lost. See Downgrades. |

`RecordingStudioStripe::DomainEvents::TRIAL_STARTED`, `INVOICE_PAID`, and `PLAN_DOWNGRADED` are those names. `SCHEMA_VERSION` is `1`.

Every payload includes `schema_version`, `occurred_at`, `id` (this event's UUID), `subscription_id`, `customer_id`, and `root_recording_id`. Those ids are local UUIDs. Replay publishes the same row, so the UUIDs stay put.

`invoice_paid` also includes:

- `amount`, Stripe `amount_paid` in the smallest currency unit
- `currency`
- `invoice_id`, the Stripe invoice id (`in_...`). There is no local invoice row
- `billing_reason`, Stripe's reason (`subscription_create`, `subscription_cycle`, and the rest)
- `subscription_status`, the local status when the event was recorded. `canceled` is not a conversion signal
- `first_payment`

`amount_paid` of 0 is not a payment. That includes a free trial invoice and a 100% coupon. It does not emit `invoice_paid` and it does not count toward `first_payment`. `invoice.paid` still moves `past_due` back to `active`.

A trial-fee invoice has at least one line whose local Price metadata `kind` is `trial_fee` (any casing), and no other positive line. A line with a positive amount and no price id counts as another line, so the invoice is not a trial fee. A zero-amount plan line next to the fee still counts as a trial fee. The fee does not emit and does not count toward `first_payment`. Kind comparison is case-insensitive. A zero amount is skipped before Price ids are checked, so an unknown Price on a zero invoice does not retry and does not set `prices_pending`. A positive invoice for a local Subscription whose Price is not in the catalogue yet stays stored. `past_due` still becomes `active`. The snapshot sets `prices_pending: true` and no domain-event row is written yet. `publish_pending!` loads those stored `invoice.paid` webhooks in the order they arrived, recomputes `first_payment`, and emits each invoice once. A later invoice for the same Stripe subscription is stored as `prices_pending` while an older one is still waiting, so the older invoice stays `first_payment`. That wait is bounded. `config.prices_pending_alert_after` (default 1 day) reports a pending invoice whose Price is still missing, once, and stores `prices_pending_alerted_at` on the snapshot. A later missing Subscription is a separate report, stored as `missing_subscription_reported_at`. `config.prices_pending_max_hold` (default 3 days) stops an older pending invoice from holding later ones. After that, the later invoice can be `first_payment: true`, and the older invoice stays pending and replays with `first_payment: false` if its Price syncs. `PricesPending.release!(webhook)` clears the flag under a row lock, reports that release after commit, and does not emit. Replaying a released webhook whose Price is still missing marks it `prices_pending` again. One webhook that raises during the sweep is reported and the sweep continues. Replay of one webhook does the same. A second sweep finds `prices_pending` clear and does not emit again. An invoice with no Stripe subscription id is stored and returns 200. It does not emit. An invoice whose Stripe subscription id is not in this app yet returns 503 so Stripe retries. That 503 is an ordering race: the gem logs a warning. `Rails.error.report` is for a deferred webhook that is not one of those races, and for a subscriber that raises.

`first_payment` is true when `billing_reason` is `subscription_create`, the amount is positive, the invoice is not a trial fee, and this local Subscription has no `invoice_paid` row yet. If that create invoice was a fee or zero, the next positive invoice is `first_payment` only when `metadata["payments_tracked"]` is set and no earlier `invoice_paid` row exists. Every Subscription created by this version sets that flag. The 0.13.0 migration also sets it on Subscriptions that are already `trialing` or `incomplete`, so a trial that converts to paid can still be the first payment. The migration does not set the flag for `incomplete_expired`, `active`, `past_due`, `unpaid`, `paused`, or `canceled`, so the next invoice on those rows is `first_payment: false`. That includes a `past_due`, `unpaid`, or `paused` Subscription that has never paid. That is any later invoice, not only a renewal. Two invoices for one Subscription are decided in arrival order under a row lock, not by Stripe's invoice time. Applying a new Stripe Subscription onto an existing local row does not start `first_payment` over once an `invoice_paid` row exists for that local id. A refund does not clear `first_payment` and does not emit another event. Rebuilding a missing row computes `first_payment` again. A row that is already stored keeps the value it was saved with.

Delivery is at-least-once. The row takes a lease (`publish_claimed_at`) before the notification. `published_at` is set only after the notification returns. A crash during the notification leaves the lease, and the sweep retries it after the lease expires. The lease defaults to 5 minutes (`config.domain_event_publish_lease`). Set it longer than the slowest synchronous subscriber chain, so a slow subscriber does not lose the lease to the sweep. The claim is a `publish_claim_token`. A late release or finish from an expired publisher does not clear the publisher that holds the token now. A subscriber that raises is reported with `Rails.error.report(handled: true)`, the lease is cleared, `publish_attempts` goes up by one, and that count is in the report context. There is no retry cap. The webhook still returns 200. Dedupe on `payload[:id]`. Schedule `RecordingStudioStripe::DomainEvents.publish_pending!(older_than:)`, the rake task `recording_studio_stripe:publish_pending_domain_events` (`OLDER_THAN_SECONDS`, default 300), or `PublishPendingDomainEventsJob`. The host should run that sweep. A fresh lease is left alone until it expires.

`occurred_at` is the Stripe event `created` time when the event came from a webhook. A local trial uses the time the Subscription was saved.

Replay with `RecordingStudioStripe::ProcessWebhook.replay(webhook_event)`. The notification waits until every open joinable transaction has committed (`ActiveRecord.after_all_transactions_commit`). The domain event row is written in the same transaction as the webhook. Replay reads the snapshot on the webhook row and does not call Stripe. A second replay, or a second delivery of the same Stripe event id, does not emit again. Webhook rows stored before this snapshot have nothing to rebuild. Saving a Subscription before the domain-events table exists does not raise. Invoice events for a host that has not migrated are dropped. Replay the stored webhook after migrating to rebuild one. A negative `table_exists?` answer is cached on the connection until the process restarts.

`invoice.paid` still moves `past_due` back to `active`, including when the invoice is a trial fee or zero.

Set `config.automatic_tax = true` only after Stripe Tax is on in the Dashboard. Checkout then also sends `customer_update: { address: "auto" }`. Promotion codes are on by default.

Hosts that do not use `current_user` should set `config.current_actor`. Hosts that do not use `current_root_recording` should set `config.current_root_recording`. Hosts that mount Stripe Admin forms must set `config.site_admin_recording`. `draw_recording_studio_stripe at:` overwrites `config.mount_path`. Billing screens use Accessible `ControllerAuth` for actor and root; grant `:view` / `:admin` on the workspace root. Accessible is required. Missing Accessible forbids billing money actions and Stripe Admin forms, and hides Manage billing on Stripe.

Recording Studio core still swallows `before_record` errors. Standing caps gate on `Recording` `before_create`, restore, and move until core can deny `record!` itself.

## Translating interface text

Customer billing and staff Admin form copy live under `recording_studio.stripe.*` (Admin forms under `admin`). This gem ships English only, in `config/locales/en.yml`. The host lists languages and supplies the translations. Put a host file at `config/locales/fr.yml` (or Japanese, or whatever you offer) with the same nested keys. Host files load after the engine, so they override English too. This gem never shipped a top-level `recording_studio_stripe.*` locale namespace.

```erb
<%= t("recording_studio.stripe.plans.title") %>
```

```yaml
fr:
  recording_studio:
    stripe:
      plans:
        title: "Tarifs"
```

Do not translate Stripe catalog data: Product names, Price amounts, staff-written card subtitles, `plan_line` templates, paywall labels, and extra card lines stay as stored. Buttons, titles, flashes, empty states, and other chrome follow I18n.

`PlansComponent` and `UsageComponent` still take `title:` and `subtitle:`. A passed string (including `nil`) wins over the translation. Leave those props unset to follow the locale.

Add [Recording Studio Internationalization](https://github.com/bowerbird-app/RecordingStudio_Internationalization) on the host when you want a language selector. This gem does not declare the host's languages.

Staff Admin form views, flashes, and resolvable Admin Definitions chrome (titles, buttons, link text, widget titles/info) use `recording_studio.stripe.admin.*`. Admin screen/section subtitles, table column headers, and cell values stay English literals (Admin search reads subtitle raw).

## Dummy

`test/dummy` is a host, not the product. Sign in at `/users/sign_in` with `admin@admin.com` / `Password`. Open `/plans` and `/pricing` for the centered plan cards. Dummy seeds Studio (Starter, Pro, Team) and Inbox (Inbox, Inbox Plus, Inbox Pro) so one workspace can hold two live plans. Pro offers a $1, 14-day trial. Cards sort cheapest first and list caps, included usage, and ticked features. Home is the workspace. `/billing` is the plan and Stripe portal. See usage appears after a live plan has recorded cap or meter use. `/billing/usage` shows the press kit cap with meters as full-width rows. `/press_kits` is where you add them; Starter caps them at 3. Admin is `/admin`.

Dummy offers English and French. French keys live in `test/dummy/config/locales/fr.yml`. The engine does not ship French. Customer pages use Recording Studio's default layout and do not add a language selector to the top nav.

Dummy credentials (`test/dummy/config/credentials.yml.enc`) are encrypted with the shared RecordingStudio_* development master key. Set `RAILS_MASTER_KEY` or put that key in `test/dummy/config/master.key` (gitignored). Keep the encrypted file; do not generate a per-repo dummy key. Stripe keys stay in `STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET`, not Rails credentials.
