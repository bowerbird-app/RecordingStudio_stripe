# Migration Notes

## Current Requirements

- Ruby 3.3 or newer
- Rails 8.1 or newer
- Recording Studio `>= 7.0, < 8.0` (gemspec). Development pin is GitHub tag `v7.0.0`
- Accessible `>= 0.43.1, < 1.0` (GitHub tag `v0.43.1`)
- `view_component` `>= 4.14, < 5` (this repo locks `4.19.0`)
- FlatPack `>= 0.1.360` (UsageMeter `limit: 0`, Button form submit). This repo pins GitHub tag `v0.1.360`

## Checkout webhooks

`0.29.1` does not add a migration. Bump the gem pin. There is no host config change. When Stripe is configured, checkout stores the price, status, and period from the Subscription, and it stores the event time. An older checkout does not replace a later subscription change. A failed Subscription read returns 503 so Stripe retries. Local mode still uses the price on the checkout session.

## Roots

`0.29.0` follows Recording Studio 7. `root_recording_for` only finds a root. `Billing.for`, which `Billable#billing` calls, uses `create_root_recording!`. The first call creates the workspace root and one `created` event when `config.actor` (or an explicit actor) is present and `authorize_write` allows `root_recording: nil`. A later call returns that root and does not append another event. `config.site_admin_recording` stays a lookup. A missing admin root is nil.

Seeds that used to create a root by looking it up call `create_root_recording!` with an actor. Dummy `authorize_write` allows a persisted user when `root_recording` is nil, then keeps the Accessible role check for later writes.

Admin `2.15.0` removed `site_admin_recording_resolver`. `AdminSupport` sets Accessible `admin_root_resolver` with `||=`. The dummy sets that resolver to the Studio Admin root and points Admin `access_recording_resolver` at `RecordingStudioAccessible.admin_root`.

Development pins: Trashable `v0.16.1` (`require: false`), Admin `v2.16.0`, Root Switchable `v0.15.1`, Internationalization `v0.2.3`. Logs stay `v0.7.4`. Metrics stay `v0.8.0`. Cache stays `v0.6.3`. No Stripe migration. No webhook change.

## Kept recordings

`0.28.0` counts live rows with `Recording.kept`. It no longer writes `where(trashed_at: nil)` or checks that the `trashed_at` column exists. Core `6.14.0` applies whatever filters an addon has registered. With none registered, `kept` returns every recording.

Trashable is not a gemspec dependency. Development and the dummy pin GitHub tag `v0.16.0` (`require: false`). Accessible `0.42.0` requires Trashable `~> 0.10`, `>= 0.16.0` and loads its query entry, which registers the kept filter. That release no longer calls `recording_studio_trashable_kept_sql`. Hosts that count inventory need Trashable `0.16.0` so trashed rows stay out of the count.

Copy core migration `20261114090000_add_root_recording_id_to_recording_studio_events` before writing events on Recording Studio `6.9.0` or newer. The dummy app includes that copy. No Stripe migration. No webhook change.

## No-plan base and byte sizes

`0.27.0` renames `no_plan_ceiling` to `no_plan_limit`. There is no alias. Set it on a count, quantity, or per-item limit when a workspace with no live plan should keep a base. Omit it and that case stays none (nil ceiling for per-item). A live plan's `limit_<name>` wins, including a blank or 0, which means none. Cancel compares every kind with `no_plan_limit`. A lower base is a lowered limit. Nothing is deleted. New writes stay blocked, and `/billing/usage` shows the meter over the base. `unit: "bytes"` prints human sizes for every aggregation. The Admin field stays a raw integer.

A limit may set `action` to `upgrade` or `purchase`. `upgrade` links to the plans page. `purchase` needs `action_url` (a path or a callable). `action_label` replaces the button text. Leave `action_method` off for a link. `post`, `put`, `patch`, or `delete` submits a form. The button appears on a zero cap, and when the usage bar is warning or danger (80% or more). Omit `action` and the card stays text only. The usage card does not show a status alert. The billing plan card still does. A zero cap uses UsageMeter `limit: 0` ("None on plan"). Copy for a workspace with no live plan does not say "this plan". Set `display` to `count` (the default) or `percent` on a limit or a meter. Percent reads `75%`. Count stays `3 of 4`, and byte caps stay sizes. Hosts need Flatpack `0.1.360` or newer.

No database migration. No webhook change.

## Usage meters

`0.26.0` draws meter and limit cards with `FlatPack::Billing::UsageMeter`. The bar warns at 80% and turns danger at the cap. A zero cap is a muted line, because UsageMeter rejects a max of 0. A nil cap is Unlimited, with no bar. Count and quantity caps still use 0 for none. A meter that mixes included usage and extra packs puts that split in the meter's description. The percent label, the `used/included` line, and the Breakdown dropdown are gone. The status alert is unchanged: over the cap, and within 15% of the included amount. `AllowanceCardComponent` is still the pack checkout button. No database migration. No webhook change. Hosts need Flatpack `0.1.356` or newer.
- Trashable GitHub tag `v0.16.1` (`require: false`)
- Admin dummy tag `v2.16.0` and Logs dummy tag `v0.7.4`
- Root Switchable GitHub tag `v0.15.1`
- Metrics dummy tag `v0.8.0`
- Cache dummy tag `v0.6.3`
- Internationalization dummy tag `v0.2.3`
- Public RubyGems and GitHub access for dependency installation

## Downgrade timing

`0.23.0` adds optional `downgrade_timing` on each `config.subscription_types` entry. Omit it, or set `at_period_end`, and downgrades still wait for renewal and cancels still wait for period end. Set `immediately` to switch the Stripe Price now (proration credit) and to end a cancel now. Unknown values raise when the initializer assigns `subscription_types`.

No database migration. Webhook projection now also emits `plan_downgraded.recording_studio_stripe` when a change that has taken effect drops a paywall or lowers a limit, including a cancel and a Subscription Stripe ends after failed payments. A per-item `limit_<name>` that is missing or blank is unlimited, same as `LimitHandle#raw_ceiling`. Cancel compares every kind with `no_plan_limit` (nil is unlimited for per-item, and none for count and quantity). A live plan still treats a missing or 0 count or quantity key as none. In the payload, `from: nil` on a per-item row means the old plan was unlimited. Subscribe if another gem should clean up. Handlers must be safe to run twice. Dedupe on `payload[:id]`. `trial_started` and `invoice_paid` are unchanged. A `$0` invoice still does not emit `invoice_paid`.

## Whole-credit usage

`0.22.0` adds a nullable `breakdown` jsonb column on `recording_studio_stripe_usage_entries`. Copy the migration and run it:

```bash
bin/rails generate recording_studio_stripe:migrations
bin/rails db:migrate
```

Existing `spend_usage` rows stay valid. They still store `usage_key`, `source_quantity`, and `credit_rate` together. `record_credits` rows store `usage_key` and `breakdown` on the `credits` meter and leave the rate columns empty. No webhook change. Hosts that do not call `record_credits` see the same spend behavior, plus the new column.

## Per-item ceilings

`aggregation: "per_item"` is optional. Leave it unset and count limits, quantity limits, plan cards, usage, and the Recording create gate stay as they are. No database migration. No webhook change.

Configure it on `config.limits`. The plan number stays Product metadata `limit_<name>`. `LimitHandle#ceiling` is that number while the workspace has a live plan in the limit's subscription type (`active`, `trialing`, or `past_due`). A live plan that omits the key leaves `ceiling` nil. nil means the consumer gem applies its own max and this gem does not add one.

A workspace with no live plan, including a canceled plan, receives `no_plan_limit` when that positive integer is set. Omit `no_plan_limit` and a plan-less workspace also has a nil ceiling. Call `enforce_item!`. The HTML redirect and JSON `403` `plan_limit_reached` response are the same as the other limits.

## Layout

`RecordingStudioStripe.configuration.layout` is the engine layout setting.

- `nil` uses `RecordingStudio.configuration.layout`, then `"recording_studio/default_layout"`
- A String is that layout name
- `false` renders with no layout
- A callable takes `controller:` and returns a String, `nil`, or `false`

Engine controllers call `recording_studio_layout { RecordingStudioStripe.configuration.layout }`. Do not set `layout "recording_studio/default_layout"` and do not include `RecordingStudio::UsesDefaultLayout`.

`PlansComponent` takes `density:` (`:auto`, `:cards`, or `:rows`). The default `:auto` is a compact row below `md` and the four-row subgrid card from `md`. `:cards` keeps the tall card at every width. `:rows` keeps the compact row at every width. `PlanCardComponent` defaults to `:cards`. Checkout on a plan card is one `form_with` around a single Flatpack submit button. Desktop amounts sit on one baseline. Extra trial padding sits above the amount. On a phone the trial badge sits after the plan name. `config.layout` does not set density. Anything else raises `ArgumentError`. No database migration. No webhook change.

`CurrentPlanComponent` on `/billing` paints Trial with FlatPack badge `style: :primary` and the plan name with `PageTitle` `variant: :h2`. Current stays `style: :success`. The group name is muted `--text-xs` text above the plan name when more than one subscription type is configured. Status badges sit top-right. Relative timing from `current_period_end` sits in brackets after the price ("$29/month (Trial ends in 2 days)", "$29/month (Renews in 21 days)", or today). `/plans` cards stay `h3`. `stripe_card_stack` lays those card bodies out with FlatPack `Collection` (`as: :list`, `layout: :stack`, `gap: :md`). Admin pricing-card headings use `SectionTitle`. `density: :rows` What’s included is FlatPack `Collapse` (`open: false`, `border: false`). `density: :auto` still uses a native `details` sibling of the feature list.

Page titles use `content_for :title` and `content_for :subtitle`. Back and close use `flat_pack_page_nav`. The right side of the top nav uses `register_page_nav` or `content_for :page_nav_right`. `/plans` centers its title and subtitle in `PlansComponent` and does not set `content_for :title`. Those headings, and each group heading, use `fp-on-backdrop`. That class changes text only when the layout has a background image. Plan cards are outside it. Interval pills use `track: true` and `style: :primary`, and set the pill list background token to the surface background. The track class includes `mb-4`, so the switch stays clear of the plan cards. The page title uses `size: :display`. Each group title on a multi-group page has a divider above it. Over a layout photo the rule uses `--backdrop-muted-content-color`. Without a photo it keeps the surface border.

`recording_studio_background_image(url)` writes `content_for :background_image`. The default layout passes that URL to `FlatPack::PageLayout` as a decorative image (`alt=""`, `loading="lazy"`). A blank URL leaves the page unchanged. `/plans` passes `config.plans_background_image`. That setting defaults to nil. `recording_studio_page_width(:wide)` writes `content_for :page_width`. Allowed values are `:narrow`, `:default`, `:wide`, and `:full`. A blank value stays `:default`. A host layout that replaces the default reads both slots.

## Verification

Install both bundles and run the complete gem and dummy app test path:

```bash
bundle install
BUNDLE_GEMFILE=test/dummy/Gemfile bundle install
bundle exec rake test:all
bundle exec rake recording_studio:check_layouts
```

Run the dummy app from its directory for browser verification:

```bash
cd test/dummy
bin/dev
```

Use the [FlatPack repository](https://github.com/bowerbird-app/flatpack) and the live FlatPack demo linked from the top-level README for current component documentation.
