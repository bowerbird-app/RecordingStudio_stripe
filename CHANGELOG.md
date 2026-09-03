# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1] - 2026-09-03

### Added
- Configuration reads Cursor Cloud secret names `Stripe_secret_key`, `Stripe_publishable_key`, and `Stripe_webhook_secret` when the canonical `STRIPE_*` names are blank
- Dummy sandbox tests that create a Product, Customer, Checkout Session, and Subscription against Stripe test mode when a test-mode secret is present
- Checkout Sessions send `integration_identifier` so hosted Checkout can be spotted in the Stripe Dashboard

### Changed
- Dummy `SeedDemoCatalog` creates or reuses Stripe Products and Prices when keys are set, instead of keeping `prod_local_` ids that Checkout cannot charge
- Checkout, extra packs, and Manage billing on Stripe turn Turbo off on the form so the browser can leave for Stripe. A fetch follow of `checkout.stripe.com` is blocked by CORS.

### Upgrade notes
- Set `STRIPE_SECRET_KEY` and `STRIPE_PUBLISHABLE_KEY`. Cloud Agent secrets named `Stripe_secret_key` and `Stripe_publishable_key` also work. Canonical names win if both are set.
- Re-run dummy seeds (or `RecordingStudioStripe::SeedDemoCatalog.call`) after adding keys so the demo catalogue exists in the Stripe sandbox.
- Dummy tests stay local. `stripe_sandbox_test.rb` hits Stripe only with `sk_test_` / `rk_test_` keys. Set `STRIPE_SANDBOX_TEST=0` to skip it. Live keys are refused.
- Turn on the Customer Portal in the Stripe Dashboard if `/billing` should open invoices and cards.

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

[0.3.1]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.3.1
[0.3.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.3.0
[0.2.1]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.2.1
