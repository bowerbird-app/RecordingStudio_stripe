# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.1] - 2026-09-09

### Fixed
- Billing, plans, and plan-change set Close to the host home. The back chevron still uses browser history, which can loop or go nowhere when those pages are a mount

### Changed
- Dummy home uses Flatpack `SidebarLayout`. Plans and billing stay on default layout as mount slices; Close still returns to that home

### Upgrade notes
- No extra migrations
- Dummy’s default layout passes `page_nav_anchor_url` as Flatpack `anchor_href`. Hosts that copied an older layout still passing `anchor_url` should do the same or Close stays hidden
- Dummy home is a host shell. Hosts pick their own chrome; this is not a gem layout change

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

[0.8.1]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.8.1
[0.8.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.8.0
[0.7.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.7.0
[0.6.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.6.0
[0.5.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.5.0
[0.4.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.4.0
[0.3.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.3.0
[0.2.1]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.2.1
