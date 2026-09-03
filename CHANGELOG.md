# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-09-02

First product cut of Recording Studio Stripe. The repo started as the addon template.

### Added
- Stripe Products, Prices, Customers, and Subscriptions projected locally on the workspace root
- Checkout for plans and one-time allowance packs
- Upgrade immediately (Stripe proration), downgrade at renewal, cancel at period end
- Usage remaining: included + purchased - usage
- Customer plans and billing pages in Flatpack on Recording Studio's default layout
- Recording Studio Admin section for Products, Prices, Meters, Customers, and Subscriptions
- Stripe webhook intake that updates local state
- Dummy catalogue (Starter, Pro, token packs) so the host app can be clicked without keys
- Plan, billing, and pack cards keep title, copy, and actions in the card body
- Prices admin lists the Product name and filters by Product or interval
- `PlansComponent` renders the plan cards. `align: :left` for a billing page. `align: :center` for a public pricing page.

### Changed
- Hosts register meters with `config.meters`. The gem writes those rows on boot. A plan Price sets included amounts per meter.
- `/plans` uses Flatpack pill buttons for monthly and yearly, so the joined segmented border is gone
- Dummy copies Recording Studio `default_layout` with `html data-theme="rounded"` so rounded tokens override `:root` on first paint

### Upgrade notes
- Include `RecordingStudioStripe::Billable` on the workspace root. Do not put a Stripe customer on User.
- `draw_recording_studio_stripe` replaces a bare engine mount.
- Copy migrations with `bin/rails generate recording_studio_stripe:migrations`.
- Point Stripe webhooks at `/webhooks/stripe`.
- Tax stays in Stripe. Do not add a local tax engine.
- Set `config.meters` for extra counters. Plan Prices store included amounts as `included_<meter_name>`.
- Render `RecordingStudioStripe::PlansComponent` on a host screen. Pass `align: :center` on a public page and `align: :left` on a signed-in billing page.

## [0.2.1] - 2026-09-01

Template environment work. See git history if you still have a copy from the gem template.

[0.3.0]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.3.0
[0.2.1]: https://github.com/bowerbird-app/RecordingStudio_stripe/releases/tag/v0.2.1
