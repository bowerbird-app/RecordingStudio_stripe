# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.16.0] - 2026-10-28

### Changed
- `PlansComponent` takes `density:` (`:auto`, `:cards`, or `:rows`). The default is `:auto`. The page wrapper sets `data-plan-density`. On a phone each plan is a compact row. The name stays on one line, the marketing subtitle hides, the price is smaller, and the feature list sits behind What’s included. From the `md` breakpoint the group is still a Flatpack Grid (two columns, then three from `lg`), and each card shares four subgrid rows (name, price, button, feature list)
- `density: :cards` keeps that tall card at every width, including a phone. `density: :rows` keeps the compact row at every width and lays the plans out with `FlatPack::Collection` (`as: :list`, `layout: :stack`, `gap: :sm`)
- `PlanCardComponent` takes the same `density:`. Its default stays `:cards`, so a host that renders one card still gets the tall card. `PlansComponent` passes its density through. `PlanCardComponent::DENSITIES` is the allowed list. An unknown density raises `ArgumentError`
- `PlanCardPrice` sizes the amount and the unit with classes. `:cards` keeps the h2 amount and the large unit. `:auto` and `:rows` use a smaller amount on a phone. `:auto` restores the h2 amount from `md`. `render(view:, price:, trial:, offer:)` still works

### Upgrade notes
- Bump to **0.16.0**. No database migration. No webhook change
- `/plans` now uses `density: :auto`. A host that wants the tall card on a phone passes `density: :cards` to `PlansComponent`
- `PlanCardComponent` still defaults to `density: :cards`. A host that renders cards itself and wants the phone row passes `density: :auto` or `density: :rows`
- Hosts that replaced `PlanCardComponent` keep their own markup. The engine page passes `density:` into that component. A replacement that does not accept `density:` raises `ArgumentError` for an unknown keyword. Accept `density:` and ignore it, or branch on `:auto`, `:cards`, and `:rows`
- `config.layout` is unchanged. It does not choose plan density
- Copy key `recording_studio.stripe.plans.included` is What’s included. Translate it in host locale files
- `PlanCardPrice` no longer sets an inline font-size. Optional `root_class:`, `amount_class:`, and `unit_class:` replace the default classes

## [0.15.0] - 2026-10-27

### Changed
- Requires `recording_studio` `>= 6.2.0` (was `>= 6.1.0`). Development and dummy pins are GitHub tag `v6.2.0`
- Engine screens still use `recording_studio/default_layout`. That layout reads `content_for :background_image` and `content_for :page_width`
- `/plans` centers its title and subtitle with `PlansComponent` (`align: :center`). It does not set `content_for :title`, so the layout does not draw a second heading
- A blank `plans.subtitle` is omitted. `PlansComponent` passes `Copy.value(@subtitle, "plans.subtitle").presence` to `FlatPack::PageTitle`. The gem English subtitle stays "Monthly or yearly. You can switch later." Dummy English no longer overrides that key, so `/plans` shows the line
- Requires `flat_pack` `>= 0.1.327`. Development and dummy pins are GitHub tag `v0.1.327`
- The plans page heading and each group heading use `fp-on-backdrop`. FlatPack applies the backdrop text tokens only when `[data-flat-pack-layout-background]` is set. The title uses the backdrop content color. The subtitle uses the muted backdrop color through the remapped surface token. Plan cards sit outside that class and keep their surface text
- Interval pills use FlatPack's pill track with `style: :primary`. The track sets `--tabs-pill-list-background-color` to `--surface-background-color`, so Monthly and Yearly sit on a light surface over a photo. The active pill uses the primary button colors. A plain `bg-` class on the pill is removed by Tailwind merge because the track's own background class comes later. The same class includes `mb-4`, so the switch stays clear of the plan cards under the page title and under each group heading
- The plans page title uses FlatPack `size: :display`. When more than one plan group is shown, a `FlatPack::Divider` sits above each group title. Over a layout photo that rule uses `--backdrop-muted-content-color`. Without a photo it keeps the surface border
- `/plans` calls `recording_studio_background_image` with `RecordingStudioStripe.configuration.plans_background_image`. The setting defaults to nil, which leaves the backdrop unset. The dummy app sets it to `/plans-backdrop.svg`
- Plan cards in a group share four subgrid rows: name, price, button, then the feature list. The button row lines up across that row of cards. A trial badge sits in the price row above the amount, and the amount sits on the bottom of that row. `PlanCardPrice` does not add its own vertical padding. A card with no Price keeps the four rows and leaves the price and button rows empty

### Upgrade notes
- Bump to **0.15.0**. Install Recording Studio **6.2.0** or newer. No database migration
- A host on Recording Studio 6.1.0 has to upgrade before this gem. Screens that set neither slot look the same
- Call `recording_studio_background_image(url)`, or set `content_for :background_image, url`. The default layout passes that URL to `FlatPack::PageLayout` as a decorative image (`alt=""`, `loading="lazy"`). A blank URL leaves the page unchanged
- Call `recording_studio_page_width(:wide)`, or set `content_for :page_width, :wide`. Allowed values are `:narrow`, `:default`, `:wide`, and `:full`. A blank value stays `:default`
- This repo does not copy `default_layout` into the dummy app. A host layout that replaces the default reads `content_for(:background_image)` and `content_for(:page_width)`
- `/plans` draws the centered title in the page. The document title on that screen falls back to the app name, because the layout uses `content_for :title` for both the tab and the heading
- Set `recording_studio.stripe.plans.subtitle` to `""` to hide that line. A host that keeps the gem translation still sees it
- Install FlatPack **0.1.327** or newer. Older FlatPack builds do not ship `.fp-on-backdrop`, so the plans title stays on the surface color over a photo
- Set `config.plans_background_image` to a public path or URL when `/plans` should show a decorative backdrop. Leave it nil to keep that page plain
- Hosts that replaced `PlanCardComponent` should render the name, price, button, and feature list as four rows of one subgrid. The grid item and the card body use `grid row-span-4 grid-rows-subgrid`. Flatpack Card rejects `style:`, and its `flex` class beats a normal `grid` utility, so the card uses `[display:grid]! [grid-template-rows:subgrid]! [grid-row:span_4]!`. Put a trial badge inside the price row and align that row to the bottom. Drop the card footer and `py-[var(--card-padding-md)]` on the price
- Hosts that replaced the interval pills should render `FlatPack::Button::Pill` with `track: true` and `style: :primary`, and set `--tabs-pill-list-background-color` to `var(--surface-background-color)` on that element. Add `mb-4` on that element so the switch stays clear of the cards. Passing `class: "bg-[var(--surface-background-color)]"` does not paint the track

## [0.14.0] - 2026-10-27

### Changed
- Requires `recording_studio` `>= 6.1.0` (was `~> 4.1`) and Accessible `~> 0.22`
- Requires `view_component` `>= 4.14, < 5`. This repo locks `4.19.0`. `flat_pack` is a direct dependency at `>= 0.1.315` (this repo pins `0.1.319`)
- `RecordingStudioStripe.configuration.layout` selects the layout for engine screens
- Customer and staff screens set `content_for :title` and `content_for :subtitle`, and call `flat_pack_page_nav` for back and close
- Cards use `background`, `border`, and `shadow` instead of `style`

### Upgrade notes
- Bump to **0.14.0**. Install Recording Studio **6.1.0** or newer, Accessible **0.22.x**, and FlatPack **0.1.315** or newer. The gemspec depends on `flat_pack` directly. `view_component` stays below 5
- Remove `include RecordingStudio::UsesDefaultLayout` and `layout "recording_studio/default_layout"` from host controllers that copied the old engine. Call `recording_studio_layout { RecordingStudioStripe.configuration.layout }`
- `config.layout` defaults to `nil`. That uses `RecordingStudio.configuration.layout`, then `"recording_studio/default_layout"`. Assign a layout name, `false`, or a callable that takes `controller:` and returns a String, `nil`, or `false`. Anything else raises `ArgumentError`
- Replace `recording_studio_page_nav` with `content_for :title`, `content_for :subtitle`, and `flat_pack_page_nav(round: true, style: :default, back_href:, back_tooltip:, anchor_href:, anchor_tooltip:)`. Put extra actions in `register_page_nav` or `content_for :page_nav_right`. Do not also render a page-level `FlatPack::PageTitle` in the view body
- `FlatPack::Card` no longer takes `style:`. Pass `background:`, `border:`, and `shadow:`
- Logs, Metrics, Cache, Internationalization, and Root Switchable may still declare `recording_studio` below 6. Load `test/support/widen_recording_studio_requirement.rb` from the host Gemfile before Bundler evaluates those gemspecs, or wait until those gems allow 6.1
- No database migration

## [0.13.0] - 2026-10-19

### Added
- `trial_started.recording_studio_stripe` after commit, once per local Subscription, when it is first saved as `trialing` or first changes to `trialing`
- `invoice_paid.recording_studio_stripe` after commit for `invoice.paid`, with `amount` (Stripe `amount_paid`), `currency`, `invoice_id`, `billing_reason`, `subscription_status`, local `subscription_id`, `customer_id`, and `root_recording_id`, and `first_payment`
- A trial-fee invoice (a `kind=trial_fee` Price line, and no other positive line) does not emit `invoice_paid` and does not count as the first payment
- `RecordingStudioStripe::ProcessWebhook.replay` republishes an unpublished domain event from the stored webhook. The webhook row keeps the invoice snapshot and subscription status used to rebuild. Replay does not call Stripe
- Table `recording_studio_stripe_domain_events`

### Upgrade notes
- Bump to **0.13.0**. Copy migrations with `bin/rails generate recording_studio_stripe:migrations`, then `bin/rails db:migrate`. A development database that already ran the removed migration `20261019140000` needs `bin/rails db:drop db:setup`. Saving a Subscription before the domain-events migration does not raise. Invoice events on a host that has not migrated are dropped. Replay the stored webhook after migrating to rebuild one. A negative `table_exists?` answer is cached on the connection until the process restarts
- Subscribe to `RecordingStudioStripe::DomainEvents::TRIAL_STARTED` and `INVOICE_PAID`. Payload `schema_version` is `1`. It includes `billing_reason` and `subscription_status`. `subscription_status` of `canceled` is not a conversion signal. Dedupe on `payload[:id]`. Delivery is at-least-once. `published_at` is set only after the notification returns. A crash keeps a lease (`publish_claimed_at`, default 5 minutes, `config.domain_event_publish_lease`) until the sweep retries it
- `first_payment` is true for a positive `subscription_create` that is not a trial fee, when that local Subscription has no `invoice_paid` row yet. Later invoices are `first_payment` only when `metadata["payments_tracked"]` is set. This version sets that flag on create. The migration also sets it for Subscriptions already `trialing` or `incomplete`, so a trial converting to paid can be the first payment. The migration does not set the flag for `incomplete_expired`, `active`, `past_due`, `unpaid`, `paused`, or `canceled`, so the next invoice on those rows is `first_payment: false`. That includes a `past_due`, `unpaid`, or `paused` Subscription that has never paid. Reusing a local row for a new Stripe Subscription does not report `first_payment` again once an `invoice_paid` row exists
- `amount_paid` of 0 does not emit `invoice_paid`, and an unknown Price on that invoice does not retry. `invoice.paid` still moves `past_due` to `active`. A positive invoice whose Price is not in the catalogue yet keeps that status change, stores `prices_pending`, and emits on replay or the pending sweep after the Price syncs. A later invoice for that Stripe subscription waits with it, so `first_payment` follows arrival order. The wait is bounded: `config.prices_pending_alert_after` (default 1 day) reports a still-missing Price once (`prices_pending_alerted_at` on the snapshot). A missing Subscription is reported separately (`missing_subscription_reported_at`), including after the Price alert. `config.prices_pending_max_hold` (default 3 days) lets later invoices emit. After that, the later invoice can be `first_payment: true`, and the older one stays pending and replays with `first_payment: false` if its Price syncs. `PricesPending.release!(webhook)` clears the flag under a row lock, reports after commit, and does not emit. Replaying a released webhook whose Price is still missing marks it pending again. One webhook that raises during the sweep is reported and does not stop the rest. An invoice with no Stripe subscription id returns 200. An unknown Stripe subscription id returns 503. Ordering races are logged. Other deferred webhooks are reported
- Schedule `recording_studio_stripe:publish_pending_domain_events` or `PublishPendingDomainEventsJob`. The sweep retries with no cap. Each failed notification increments `publish_attempts` and puts that count on the error report. No new Stripe dependency, and no dependency on Conversions
- Webhook rows from older versions have no invoice snapshot. Replaying those does not invent an event

## [0.12.1] - 2026-10-16

### Changed
- Development and dummy pins for `recording_studio_trashable` moved from `v0.10.0` to `v0.11.0` (Git tag `v0.12.1`)

### Upgrade notes
- No application migration and no gem API change. The version constant on that tag stayed `0.12.0`. Install trashable `0.11.0` when you follow the dummy Gemfile pins

## [0.12.0] - 2026-10-14

### Changed
- Billing `ApplicationController` uses `RecordingStudioAccessible::ControllerAuth` for actor, root, and require-root (stripe-shaped options: no authenticate before_action, `require_actor`, resolvers, plain responses)
- Depends on `recording_studio_accessible` `~> 0.18` (was optional via the host/dummy only)
- `authorize_role!` stays on the gem: Accessible when loaded, otherwise `config.authenticate`, otherwise fail closed (same as main). ControllerAuth has no authenticate fallback
- `protect_from_forgery with: :exception, prepend: true` is declared before `ControllerAuth` so `:verify_authenticity_token` runs ahead of host auth and require-root filters

### Upgrade notes
- Bump to **0.12.0** and install Accessible **0.18.x** (pin GitHub tag `v0.18.0` until a newer 0.18.x tag ships)
- Public controller methods stay the same: `current_actor`, `current_billing_root`, `require_root_recording!`, `authorize_view!` / `authorize_edit!` / `authorize_admin!`, `config.authenticate`. `current_billing_root` is not a view helper (same as main; only `billing` is)
- `config.current_actor` and `config.current_root_recording` still override host helpers. No migration

## [0.11.0] - 2026-10-12

### Added
- Staff Admin flashes, “Staff only.”, and Admin Definitions chrome that the Admin gem resolves at render (section/screen titles, nav link text, screen buttons, row actions, widget titles/info) resolve through `recording_studio.stripe.admin.*` with English `default:`
- Regression test scans every `lib/**/*.rb` and refutes `i18n.load_path` / `I18n.load_path`
- Dummy always-loaded host override on rarely shown `admin.plan_card.hide_aria` (boot-order guard), plus render-level flash/staff-only/definition assertions

### Changed
- Admin controller notices and forbidden plain text use `Copy.t(..., default:)` (English output unchanged)

### Upgrade notes
- Bump to **0.11.0** (minor: hosts can translate Admin flashes and resolvable Definitions chrome). No migration
- English output stays the same. Admin screen/section **subtitles** stay English literals (Admin search reads subtitle raw). Admin column headers remain untranslated. **Cell values** stay English literals
- Model validation messages and lib/service raised messages stay main’s English; translate only at controller/view render sites
- Hosts override with the same nested keys under `recording_studio.stripe.*`. No engine `i18n.load_path` initializer
- Public helpers and `RecordingStudioStripe::Copy` are unchanged

## [0.10.0] - 2026-10-09

### Added
- Staff Admin form copy (Products, Prices, Meters, Paywalls under the engine) resolves through `recording_studio.stripe.admin.*` I18n keys
- English keys ship in `config/locales/en.yml` under `en.recording_studio.stripe.admin`

### Changed
- Admin form views under `app/views/recording_studio_stripe/admin` use `t("recording_studio.stripe.admin...")` (English output unchanged)

### Upgrade notes
- Bump to **0.10.0** (minor: hosts can translate staff Admin forms). No migration
- English Admin forms stay the same. Catalog data (Product names, Price amounts, paywall/meter labels, card extras) is still not translated
- Admin section/screen chrome from `RecordingStudioStripe::Admin::Definitions` (list titles, table column headers, “New Product” buttons) stays English hard-coded; only the gem’s own form views moved
- This gem never shipped a top-level `recording_studio_stripe.*` locale namespace. Host overrides use `recording_studio.stripe.*` (including the new `admin` branch)
- To translate Admin forms, copy `recording_studio.stripe.admin.*` from `config/locales/en.yml` into the host locale file
- Public helpers and `RecordingStudioStripe::Copy` are unchanged

## [0.9.0] - 2026-10-08

### Added
- Customer billing copy resolves through `recording_studio.stripe.*` I18n keys
- Engine ships English only in `config/locales/en.yml`
- Dummy hosts English and French, with a language selector in the top nav

### Upgrade notes
- Bump to **0.9.0** (minor: hosts can translate customer billing screens). No migration
- English screens stay the same. Leave `PlansComponent` / `UsageComponent` `title:` and `subtitle:` unset to follow the locale. A passed string, including `nil`, still wins
- To offer another language, copy `recording_studio.stripe.*` from `config/locales/en.yml` into the host (`config/locales/fr.yml` is the dummy starting point) and list that locale on the host. Add Recording Studio Internationalization when you want the language selector
- Do not expect a French file from this gem. Product names, prices, and other stored catalog copy are not translated
- Staff Admin screens stay English

## [0.8.9] - 2026-09-30

### Added
- Standing limits accept `aggregation`: `count` (default) or `quantity`
- `RecordingStudioStripe.register_limit_usage` (and `config.register_limit_usage`) supplies the current integer for a quantity limit
- `LimitHandle#enforce!` and `LimitHandle#with_capacity!` raise `PlanLimitReached` when the requested quantity does not fit
- `with_capacity!` runs the write in the same transaction as the check, under a Postgres advisory lock for that root and limit

### Changed
- `LimitHandle#available?` requires a positive integer, the same rule as `enforce!` and `with_capacity!`. Calling it with no argument still checks 1

### Upgrade notes
- Existing `config.limits` entries stay count limits. Omit `aggregation` and press-kit caps keep working, including create, restore, and move
- A quantity limit does not need `recordable_type`. Register a usage provider before reading `used`. A missing provider raises `ArgumentError`
- The provider receives the root recording and must return a non-negative integer. Negative or non-integer results raise `ArgumentError`
- Product metadata is still `limit_<name>` on the Product. Monthly and yearly Prices share it. Nothing resets on a billing period
- Recording create, restore, and move enforce count limits only. Call `with_capacity!` from the gem that knows the quantity
- Put the usage write inside the `with_capacity!` block, on the same database connection. `enforce!` does not reserve capacity for a later transaction
- Postgres holds the advisory lock until that transaction ends. Other databases skip the lock, as they do for count creates
- A quantity `PlanLimitReached` says “Upgrade, or free some up.” Count copy is unchanged
- `available?` raises `ArgumentError` for 0, a negative integer, a float, a string, or nil. `available?` and `available?(1)` stay valid
- No extra migrations

## [0.8.8] - 2026-09-30

### Added
- `config.usage_costs` maps a usage key to the credits one unit costs
- `RecordingStudioStripe.usage_cost` returns that rate. An unknown key raises `ArgumentError`
- `Billing#spend_usage`, `Billing#usage_cost`, and `Billing#usage_available?`, with the same methods on `Billing::Line`
- A weighted spend stores `usage_key`, `source_quantity`, and `credit_rate` on the usage row. `quantity` stays the credits deducted

### Upgrade notes
- Copy the new migration with `bin/rails generate recording_studio_stripe:migrations`, then run `bin/rails db:migrate`
- Add a `credits` meter in `config.meters` and set `included_credits` on each plan Price that sells credits
- A credit pack stays a one-time allowance Price. Set `meter` to `credits` and `allowance` to the pack size
- `spend` and `record` stay the same when no usage source is passed. Passing `usage_key`, `source_quantity`, or `credit_rate` on a meter other than `credits` raises `ArgumentError`
- When more than one live plan holds credits, call `billing.line`. `billing.spend_usage` raises `AmbiguousSubscriptionLine` instead of picking a plan
- When more than one subscription type is configured and no live plan holds credits, `billing.spend_usage` raises `SubscriptionLineRequired`. It does not pool line-scoped packs into an untyped balance
- An idempotency key is unique for the workspace root. Use a fresh request id for each billable operation. Reusing a key across lines or events returns the original usage row

## [0.8.7] - 2026-09-25

### Added
- `week` is a recurring Price interval beside `month` and `year`. One Price per Product per interval
- `Product#weekly_price` and `Product#price_for` pick the card and the sort for that interval
- Weekly pill on plan cards when that group has a weekly Price. `PlanIntervals#hrefs_for` adds `weekly_href`
- `stripe_plan_intervals` lists the intervals that have a Price. Pass `intervals:` on `PlansComponent` to limit that list
- Admin new Price can be Week. The Prices list can filter on `week`

### Changed
- A weekly card amount is `$9/wk`, flush against the amount, same as `/mo` and `/yr`
- Same Product: week to month to year is an upgrade. The shorter interval is a downgrade
- Across Products, a blank rank compares a monthly equivalent. Weekly amount times 52 divided by 12. Yearly amount divided by 12
- A local checkout on a weekly Price ends the period one week out
- `CreatePrice` accepts week, month, year, or a blank one-time interval
- An interval pill shows only when that group has a Price for it. The card row includes only Products that have that Price
- When that interval has no Price, cards use the first offered interval. An `intervals:` limit that matches nothing leaves the grid empty

### Upgrade notes
- No extra migrations. Existing month and year Prices stay as they are
- Hosts that replaced `PlansComponent` pills should call `stripe_plan_intervals(products)` and show a pill only for an interval in that list, and only when its href is set. Pass `intervals:` to keep a page on month and year, or on week alone
- The plans grid drops a Product that has no Price for the interval on screen. `PlanCardComponent` still says "No week Price yet" when a host renders that card directly
- A requested interval with no Price in the offered list falls back to the first interval that has one. Pass `intervals:` when that fallback should stay inside a shorter list
- Hosts that replaced `PlanCardComponent` should use `product.price_for(interval)` and `/wk` for a week Price
- Same-product interval order is week, then month, then year
- `CreatePrice` rejects any other interval. A webhook upsert still stores the interval Stripe sends
- Trials are unchanged. `trial_period_days` stays in days, including on a weekly Price
- The default page subtitle stays “Monthly or yearly. You can switch later.” Pass `subtitle:` on `PlansComponent` when you sell weekly

## [0.8.6] - 2026-09-21

### Added
- Optional subtitle under the plan name on a pricing card. Staff set it next to the name. It stays in local `plan_card` metadata. `Product#card_subtitle` reads it

### Changed
- Plan card prices sit above the button, at the page-title h2 size, with `/mo` or `/yr`, and a little space above the badge and below the amount
- A trial card strikes the plan price with its interval (`$29/mo`), shows the trial amount, a space, then the word trial (`$1 trial`), and adds a duration badge such as 14 day trial or 1 month trial
- That card's button says Try now. Upgrade, Downgrade, and Current plan stay when the workspace is already on a plan in that group

### Upgrade notes
- No extra migrations
- Hosts that replaced `PlanCardComponent` should move the price into the footer, above the button
- Hosts that replaced `PlanCardComponent` should strike the plan amount with `/mo` or `/yr`, show `product.trial.amount_label` followed by the word trial, and add a `product.trial.duration_label` badge when a trial is offered and that group has no live plan
- The trial button is Try now. `Trial#checkout_label` returns that. Plan changes still say Upgrade or Downgrade
- Hosts that replaced `PlanCardComponent` can pass `product.card_subtitle` as the title subtitle. A missing Price still uses that slot for "No month Price yet" or "No year Price yet"

## [0.8.5] - 2026-09-18

### Added
- Optional paid or $0 trial on a plan Product through `RecordingStudioStripe::Trial`
- `AssignTrial` writes trial metadata and a one-time `kind=trial_fee` Price on that Product
- Checkout sends `trial_period_days`, the fee line item when the amount is above 0, and `payment_method_collection: always` when the group has no live plan
- Dummy Pro seeds a $1, 14-day trial

### Changed
- Checkout webhooks persist Stripe's subscription status, including `trialing`
- Plan cards say Try for $1, or Start trial when the amount is 0, when a trial is offered and there is no live plan
- Billing trial subtitle names the end date and the plan price that starts after
- Admin plan new and edit have a Paid trial section

### Upgrade notes
- No extra migrations
- Set Trial days and Trial amount in cents on a plan Product. Empty days means no trial. 0 cents is a free trial on the same path
- Hosts that replaced `PlanCardComponent` should use `product.trial.checkout_label` when `product.trial.offered?` and there is no live plan in that group
- Hosts that replaced billing copy should name the trial end date and that the plan price starts after
- `invoice.paid` still only moves `past_due` to `active`. Trial end still comes from `customer.subscription.updated`
- `UpsertProduct` keeps local trial metadata when Stripe omits those keys. Create and Update send `trial_days` and `trial_unit_amount` on Stripe Product metadata

## [0.8.4] - 2026-09-18

### Added
- Customer usage page at `/billing/usage` for standing caps and period meters
- `UsageComponent` so hosts can render that block on their own screen
- `config.usage_path` (defaults to `{mount_path}/usage`)

### Changed
- `/billing` is the money page. Caps and meters live on usage
- HTML `MeterLimitReached` redirects to usage, not billing
- Dummy sidebar has Usage
- Usage cards are one full-width row. Cap copy is `used/included` above the bar
- Usage does not title each live plan group (no Studio usage heading)
- A meter that mixes plan include and extra packs has a Breakdown dropdown for that sum
- Billing See usage only when a live plan has recorded cap or meter use
- Billing no longer titles each live plan with the group name
- Live plan badge is Current in the success colour. The type badge sits after it when more than one type is configured
- Signed-in `/plans` is titled Pricing, centered like public `/pricing`
- Cheaper plan changes say Downgrade, not Switch at renewal
- Studio and Inbox section titles only appear when more than one plan type has Products

### Upgrade notes
- No extra migrations
- Usage moved off `/billing` to `/billing/usage`
- Hosts that replaced `billing/show` should drop the meter and cap cards, or render `UsageComponent`
- Hosts that replaced `billing/show` should hide See usage until a live plan has recorded cap or meter use
- Hosts that replaced `CurrentPlanComponent` should show Current (success) instead of Active (primary), and put the type badge after status only when more than one subscription type is configured
- Hosts that replaced `LimitCardComponent` should put `used/included` above the bar
- Hosts that replaced `UsageComponent` should render one full-width card per metric, with no group heading
- Hosts that replaced `MeterCardComponent` should show Breakdown when included and purchased are both positive
- Set `config.usage_path` if usage is not `{mount_path}/usage`
- HTML meter-limit redirects go to usage
- Dummy sidebar Billing is not current on `/billing/usage`
- Hosts that replaced `plans/index` should title the page Pricing and pass `align: :center`
- Hosts that replaced `PlanCardComponent` or `PlanChange` should label a cheaper plan Downgrade
- Hosts that replaced billing empty or dummy home should say See pricing

## [0.8.3] - 2026-09-18

### Added
- Manage billing on Stripe uses the gem's `:stripe` Flatpack button style
- `recording_studio_stripe/button` paints that style with Stripe blurple (`#635bff`) and navy hover (`#0a2540`)

### Changed
- Dummy Flatpack pin is `v0.1.189` so `register_style` is available

### Upgrade notes
- Hosts need Flatpack 0.1.189 or newer for `register_style`
- The billing view loads `recording_studio_stripe/button` through `content_for :head`
- If the host layout does not yield `:head`, link that stylesheet after Flatpack
- Update card, Cancel, Change plan, and See plans stay on their current styles
- No extra migrations

## [0.8.2] - 2026-09-16

### Added
- Cancel at period end opens a confirmation page that names the plan and the end date
- Stay on the current plan clears a scheduled downgrade
- Billing shows a wait alert for extra-pack return and for an incomplete Checkout

### Changed
- `past_due` and `trialing` use their own badges. Past due offers Update card
- Plan-change secondary is Never mind. Billing Cancel still ends the plan
- Billing no longer lists extra packs

### Upgrade notes
- No extra migrations
- A `past_due` plan still counts as subscribed. Paywalls and caps stay on until Stripe cancels
- The plan card Cancel control is now a GET to `subscription_cancel_confirm_path`. POST `subscription/cancel` still ends the plan
- Hosts that replaced `CurrentPlanComponent` should show Past due / Trial / Update card / Stay on {plan}, and send Cancel through the confirm page
- Plan-change Confirm secondary is Never mind, not Cancel
- Default `/billing` no longer renders extra packs. `AllowanceCardComponent` and POST `allowances` still work if a host puts them on their own screen

## [0.8.1] - 2026-09-09

### Added
- Plan cards list ticked paywalls as well as standing caps and included usage
- Optional `icon` and `plan_line` on limit, meter, and paywall config for that card copy
- Optional Product `plan_card` metadata to hide, reorder, or add a display-only line

### Fixed
- Billing, plans, and plan-change set Close to the host home. The back chevron still uses browser history, which can loop or go nowhere when those pages are a mount

### Changed
- Dummy home uses Flatpack `SidebarLayout`. Plans and billing stay on default layout as mount slices; Close still returns to that home
- Public pricing centers the page title and subtitle with the cards
- Plan group names (Studio, Inbox) only show when more than one type has Products
- Plan cards sort cheapest first for the interval on the page
- Dummy catalogue has three Studio plans and three Inbox plans, each with month and year
- Plan cards use a Flatpack list with an icon on each line
- Plan cards in a group share height. The action sits in the Flatpack card footer. The row is a Flatpack Grid that stretches
- Admin plan edit names the plan, groups features with caps, and puts pricing-card lines in a disclosure

### Upgrade notes
- No extra migrations
- Dummy’s default layout passes `page_nav_anchor_url` as Flatpack `anchor_href`. Hosts that copied an older layout still passing `anchor_url` should do the same or Close stays hidden
- Dummy home is a host shell. Hosts pick their own chrome; this is not a gem layout change
- A host with one subscription type no longer sees that type name above the cards. Configure a second type with Products if the heading should stay
- Plan cards now sort by Price, cheapest first, for the interval on the page. They are not alphabetical by Product name
- Cards now list paywalls ticked on the Product. Hosts that relied on cards never showing those features will see them
- Optional `icon` and `plan_line` on `config.limits`, `config.meters`, and `config.paywalls`. Omit them to keep today’s default copy
- Optional `metadata["plan_card"]` (`hide`, `order`, `extras`) stays local. It is not sent to Stripe
- Hosts that replaced `PlanCardComponent` should put Choose, Upgrade, and Current in the card footer so cards in a group share height
- Admin Edit Product is now Edit with the plan name. Save is Save. Pricing-card hide, order, and extra lines sit in a disclosure. Extra lines no longer ask for a key on the form

## [0.8.0] - 2026-09-08

### Added
- Upgrade and plan switch open a confirmation page that names the new price, the current price, and when the change takes effect

### Changed
- Plan cards link to that confirmation page. Checkout for a group that already has a live plan redirects there instead of applying immediately
- The confirmation back-out button is Cancel

### Upgrade notes
- No extra migrations
- Hosts that replaced `PlanCardComponent` should send Upgrade and Switch at renewal to `subscription_change_path` instead of PATCHing `subscription_path` from the card
- PATCH `subscription_path` still applies the change. That is the confirm button

## [0.7.0] - 2026-09-07

### Added
- Recurring Checkout reserves an incomplete local row under an advisory lock so two first Checkouts in the same group cannot mint two Stripe Subscriptions
- `checkout.session.async_payment_succeeded` fulfils a paid Checkout
- Usage and allowance rows store `subscription_type` so Studio and Inbox meters no longer share one pool
- `config.authenticate` runs only when Accessible is not loaded. Missing both fails closed
- `Meter.fetch` raises for unknown names. `Meter.named` finds only

### Changed
- Checkout, extra packs, plan change, cancel, resume, and the Stripe portal require Accessible `:admin` on the workspace
- `checkout.session.completed` fulfils only when `payment_status` is `paid` or `no_payment_required`
- Stripe upgrades use `payment_behavior: error_if_incomplete` and wait for the webhook before changing the local Price
- Subscription webhooks ignore an event whose `created` is older than the row already applied
- `RecordNotUnique` is a duplicate only for webhook event ids. Other unique failures raise
- Recurring Checkout idempotency keys are unique per attempt
- `automatic_tax` also sends `customer_update: { address: "auto" }`
- Plan change and webhook item lookup match the current Price, not always the first item
- Downgrade schedules copy every current item and quantity, and keep phase discounts
- Local `sub_local_*` ids are minted only in local mode
- Standing caps also run on parent or root moves, and only under a `:stripe` root
- Usage idempotency keys are unique per workspace. Lookups and retries are scoped to that root
- Allowance packs bought earlier in the calendar month still count after a mid-month subscribe
- Webhook rows store event id, type, created, and object id. They do not store the full Stripe object
- Cancel and resume without `subscription_type` raise when more than one live plan exists
- Edit Price can clear included usage. Create Price rejects a nonnumeric amount
- Admin uses `current_actor_method` and Admin screen URLs from the Admin mount path
- Plan cards no longer say unlimited. Billing empty copy says usage still counts. Meter bars stay default when nothing is included

### Upgrade notes
- Copy the new migration with `bin/rails generate recording_studio_stripe:migrations` then `bin/rails db:migrate`
- Grant `:admin` on the workspace for anyone who should pay, change plan, cancel, or open the Stripe portal. `:edit` can still read `/plans` and `/billing`
- Set `config.current_actor` and `config.current_root_recording` if the host does not use `current_user` / `current_root_recording`
- `draw_recording_studio_stripe at:` is the mount path. Setting `config.mount_path` first is overwritten by that helper
- Do not deploy local mode. Unsigned webhooks are accepted only when Stripe keys and client are both absent
- `Meter.named("x")` no longer creates a row. Call `Meter.sync_from_config!` or Admin first
- Hosts that recorded usage with a global idempotency key keep those rows. New writes are unique per workspace
- Recording Studio core still swallows `before_record` errors. Standing caps still gate on `Recording` `before_create`, restore, and move

## [0.6.0] - 2026-09-07

### Added
- `account.billing.meter(:ai_tokens).spend(n)` checks `available?` then records. `record` still writes the fact even when over
- `config.limit_reached_path` for the HTML redirect when a standing cap is hit (default is `/plans`)
- `config.allow_promotion_codes` (default true) and `config.automatic_tax` (default false) on Checkout
- Admin Edit Price for included usage and allowance metadata. Stripe keeps the amount
- `checkout.session.completed` now fulfils a plan Checkout. `/billing?checkout=ok` explains the wait if Stripe is still writing
- `invoice.paid` clears `past_due`. `invoice.payment_failed` marks `past_due`

### Changed
- Stripe webhook rows commit only after the handler applies. Missing catalogue or workspace returns 503 so Stripe retries
- Checkout for a live plan group calls `ChangePlan` instead of opening a second Stripe Subscription
- Plan changes read the Stripe subscription item id. They release an existing schedule, then create a schedule from the Subscription and update phases. Failed schedules no longer drop the cheaper price on immediately
- Admin Product save merges Stripe Product metadata instead of replacing it. Clearing a standing cap unsets that `limit_*` key on Stripe
- `EnsureCustomer` updates email when it changes
- `account.billing.meter(:ai_tokens)` uses the live plan that includes that meter, not the latest updated subscription
- Standing cap cards show used of included, including when over
- Dummy home is a workspace landing. Dummy `/pricing` passes the signed-in plan so Choose plan becomes Upgrade
- Recurring Checkout and Customer creates send Stripe idempotency keys. One-time pack Checkout uses a new key each attempt
- `spend` takes a Postgres lock and returns the existing row when the same idempotency key is retried
- Configured Stripe without `STRIPE_WEBHOOK_SECRET` rejects unsigned webhook bodies
- `invoice.paid` and `invoice.payment_failed` read `parent.subscription_details.subscription`, with a fallback to the older `subscription` field
- `checkout.session.completed` keeps period dates that a subscription webhook already wrote

### Upgrade notes
- Call `spend` before work that must not run over a meter. Keep `record` for logging what already happened
- Set `STRIPE_WEBHOOK_SECRET` whenever Stripe keys or a Stripe client are configured. Unsigned events only work in local mode
- Set `config.automatic_tax = true` only after Stripe Tax is on in the Dashboard
- Set `config.limit_reached_path` if your plans page is not `/plans`
- No extra migrations
- Recording Studio core still swallows `before_record` errors. This gem still gates standing caps on `Recording` `before_create`

## [0.5.0] - 2026-09-07

### Added
- Optional `config.limits` so a plan can cap how many of a recordable type exist under the workspace (not trashed)
- `account.billing.limit(:press_kits)` with `included`, `used`, `remaining`, `available?`, and `over?`
- Product metadata `limit_<name>` (Admin integer fields). Monthly and yearly of the same plan share the number
- Recording `before_create` / restore-from-trash gate that raises `RecordingStudioStripe::PlanLimitReached`
- HTML rescue redirects to `/plans` with a human flash. JSON is 403 `{ code: "plan_limit_reached" }`
- Plan cards and `/billing` show the standing cap next to meter usage
- Dummy Press kits: Starter 3, Pro 10. `/billing` shows the cap. `/press_kits` lists and adds them. A fourth create on Starter goes to `/plans`

### Upgrade notes
- Omit `config.limits` and nothing changes. No extra Stripe gem migrations
- To cap a type, set `config.limits` and the count on each plan Product in Admin (`limit_press_kits` metadata)
- `subscription_type` on a limit is optional: a matching plan group name wins, otherwise the first group
- Missing or 0 means none on that plan. Downgrades do not delete extras; `over?` is true until someone archives
- Do not `record` meter usage for these caps. Accessible stays access. This is billing
- Dummy hosts need a `press_kits` table (dummy migration) and `PressKit` on `config.recordable_types`

## [0.4.0] - 2026-09-03

### Added
- Optional `config.subscription_types` so a workspace can hold one live plan per named group on the same Stripe Customer
- `account.billing.line(:press_kits)` for that group's subscription, meters, and paywalls
- `Catalog.plan_groups` and `PlansComponent` `groups:` so `/plans` can section cards by type
- Monthly and yearly pills sit under each plan group name, left aligned, above that group's cards. `PlanIntervals` keeps the other group's cadence in the URL
- Admin plan-group picker when types are configured
- Dummy Studio and Inbox catalogues so two live plans can be clicked in local mode

### Changed
- Checkout for an empty type adds a Stripe Subscription. A Product in a type you already have still upgrades now or downgrades at renewal
- Cancel and resume take `subscription_type` and leave other live plans alone
- `unlocked?` is true when any live plan Product opens that paywall
- Meters on a line use that line's Stripe period
- Existing Product and Subscription rows get type `plan`. If the host configures exactly one type, `AssignSubscriptionTypes` remaps `plan` to that key

### Upgrade notes
- Copy migrations with `bin/rails generate recording_studio_stripe:migrations` then `bin/rails db:migrate`
- Hosts that omit `config.subscription_types` keep one implied type (`plan`) and one live plan
- To sell more than one plan at once, set `config.subscription_types` and put each plan Product in a group in Admin
- Prefer `account.billing.line(:press_kits).subscription` and `account.billing.line(:press_kits).meter(:kits).remaining`. `account.billing.subscription` is still the latest live plan
- `account.billing.unlocked?(:export_csv)` stays the any-plan check. Use `billing.line(:press_kits).unlocked?(:export_csv)` when the paywall belongs to one group
- Re-run dummy seeds after upgrade so Inbox plans exist
- Hosts that render `PlansComponent` themselves should pass per-group `interval`, `monthly_href`, and `yearly_href` through `PlanIntervals`. A leftover page-level toggle still applies to groups that omit their own. `?interval=year` still sets every group

## [0.3.0] - 2026-09-02

First product cut of Recording Studio Stripe. The repo started as the addon template.

### Added
- Stripe Products, Prices, Customers, and Subscriptions projected locally on the workspace root
- Checkout for plans and one-time allowance packs
- Upgrade immediately (Stripe proration), downgrade at renewal, cancel at period end
- Usage remaining: included + purchased - usage
- Customer plans and billing pages in Flatpack on Recording Studio's default layout
- Recording Studio Admin section for Products, Prices, Meters, Paywalls, Customers, and Subscriptions
- Stripe webhook intake that updates local state
- Dummy catalogue (Starter, Pro, token packs) so the host app can be clicked without keys
- Plan, billing, and pack cards keep title, copy, and actions in the card body
- Prices admin lists the Product name and filters by Product or interval
- `PlansComponent` renders the plan cards. `align: :left` for a billing page. `align: :center` for a public pricing page.
- Named paywalls: register names in `config.paywalls`, tick them on a plan Product, check with Accessible `authorized_action?`
- Manage billing on Stripe opens the Stripe Customer Portal for invoices and cards
- The billing portal button uses Flatpack’s `credit-card` Heroicon

### Changed
- Hosts register meters with `config.meters`. The gem writes those rows on boot. A plan Price sets included amounts per meter.
- Hosts register paywalls with `config.paywalls`. Staff tick them on a plan Product. Accessible `authorized_action?` is `:view` on the root plus that Product.
- `/plans` uses Flatpack pill buttons for monthly and yearly, so the joined segmented border is gone
- Dummy copies Recording Studio `default_layout` with `html data-theme="rounded"` so rounded tokens override `:root` on first paint
- The gem loads `ApplicationHelper` on host controllers so `PlansComponent` works outside the engine screens
- `/billing` puts the current plan in a two-column grid, with Active above the plan name in the primary badge
- Usage cards show percent used instead of remaining copy

### Upgrade notes
- Include `RecordingStudioStripe::Billable` on the workspace root. Do not put a Stripe customer on User.
- `draw_recording_studio_stripe` replaces a bare engine mount.
- Copy migrations with `bin/rails generate recording_studio_stripe:migrations`.
- Point Stripe webhooks at `/webhooks/stripe`.
- Tax stays in Stripe. Do not add a local tax engine.
- Set `config.meters` for extra counters. Plan Prices store included amounts as `included_<meter_name>`.
- Set `config.paywalls` for named plan features. Tick them on the Product in Admin. Check with `RecordingStudioAccessible.authorized_action?(action: :generate_image, recording: root)`. Copy migrations again so paywall tables exist.
- Render `RecordingStudioStripe::PlansComponent` on a host screen. Pass `align: :center` on a public page and `align: :left` on a signed-in billing page.
- Turn on the Customer Portal in the Stripe Dashboard. Manage billing on Stripe sends people there for invoices and cards. Do not copy those rows locally.

## [0.2.1] - 2026-09-01

Template environment work. See git history if you still have a copy from the gem template.

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_stripe/compare/v0.14.0...HEAD
[0.14.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/compare/v0.12.1...v0.13.0
[0.12.1]: https://github.com/bowerbird-app/RecordingStudio_stripe/compare/v0.12.0...v0.12.1
[0.12.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/compare/v0.8.9...v0.9.0
[0.8.9]: https://github.com/bowerbird-app/RecordingStudio_stripe/compare/v0.8.8...v0.8.9
[0.8.8]: https://github.com/bowerbird-app/RecordingStudio_stripe/compare/v0.8.7...v0.8.8
[0.8.7]: https://github.com/bowerbird-app/RecordingStudio_stripe/compare/v0.8.6...v0.8.7
[0.8.6]: https://github.com/bowerbird-app/RecordingStudio_stripe/compare/v0.8.5...v0.8.6
[0.8.5]: https://github.com/bowerbird-app/RecordingStudio_stripe/compare/v0.8.4...v0.8.5
[0.8.4]: https://github.com/bowerbird-app/RecordingStudio_stripe/compare/v0.8.3...v0.8.4
[0.8.3]: https://github.com/bowerbird-app/RecordingStudio_stripe/compare/v0.8.2...v0.8.3
[0.8.2]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.8.2
[0.8.1]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.8.1
[0.8.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.8.0
[0.7.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.7.0
[0.6.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.6.0
[0.5.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.5.0
[0.4.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.4.0
[0.3.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.3.0
[0.2.1]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.2.1
