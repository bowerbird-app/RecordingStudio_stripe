# Migration Notes

## Current Requirements

- Ruby 3.3 or newer
- Rails 8.1 or newer
- Recording Studio `>= 6.5.0` (gemspec). Development pin is GitHub tag `v6.5.0`
- Accessible `~> 0.24` (GitHub tag `v0.24.2`)
- `view_component` `>= 4.14, < 5` (this repo locks `4.19.0`)
- FlatPack `>= 0.1.341`. This repo pins GitHub tag `v0.1.341`
- Trashable GitHub tag `v0.12.3` (`require: false`)
- Admin dummy tag `v2.7.0` and Logs dummy tag `v0.7.4`
- Root Switchable GitHub tag `v0.11.4`
- Metrics dummy tag `v0.7.3`
- Cache dummy tag `v0.6.2`
- Internationalization dummy tag `v0.2.2`
- Public RubyGems and GitHub access for dependency installation

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

A workspace with no live plan, including a canceled plan, receives `no_plan_ceiling` when that positive integer is set. Omit `no_plan_ceiling` and a plan-less workspace also has a nil ceiling. Call `enforce_item!`. The HTML redirect and JSON `403` `plan_limit_reached` response are the same as the other limits.

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
