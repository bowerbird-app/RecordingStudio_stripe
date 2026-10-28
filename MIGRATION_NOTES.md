# Migration Notes

## Current Requirements

- Ruby 3.3 or newer
- Rails 8.1 or newer
- Recording Studio `>= 6.2.0` (gemspec). Development pin is GitHub tag `v6.2.0`
- Accessible `~> 0.22` (GitHub tag `v0.22.0`)
- `view_component` `>= 4.14, < 5` (this repo locks `4.19.0`)
- FlatPack `>= 0.1.329`. This repo pins GitHub tag `v0.1.329`
- Trashable GitHub tag `v0.12.0` (`require: false`)
- Admin dummy tag `v2.7.0` and Logs dummy tag `v0.7.0`
- Root Switchable commit `8dd47257db449120496ad64ed2ce68af600dd6cd` (`0.11.0`, Recording Studio 6.1 layout, still resolves with 6.2.0)
- Metrics dummy tag `v0.6.1`
- Cache dummy tag `v0.5.1`
- Internationalization dummy tag `v0.1.7`
- Public RubyGems and GitHub access for dependency installation

Logs, Metrics, Cache, Internationalization, and Root Switchable still declare `recording_studio` below 6. Both Gemfiles require `test/support/widen_recording_studio_requirement.rb` before Bundler loads those gemspecs.

## Layout

`RecordingStudioStripe.configuration.layout` is the engine layout setting.

- `nil` uses `RecordingStudio.configuration.layout`, then `"recording_studio/default_layout"`
- A String is that layout name
- `false` renders with no layout
- A callable takes `controller:` and returns a String, `nil`, or `false`

Engine controllers call `recording_studio_layout { RecordingStudioStripe.configuration.layout }`. Do not set `layout "recording_studio/default_layout"` and do not include `RecordingStudio::UsesDefaultLayout`.

`PlansComponent` takes `density:` (`:auto`, `:cards`, or `:rows`). The default `:auto` is a compact row below `md` and the four-row subgrid card from `md`. `:cards` keeps the tall card at every width. `:rows` keeps the compact row at every width. `PlanCardComponent` defaults to `:cards`. Checkout on a plan card is one `form_with` around a single Flatpack submit button. Desktop amounts sit on one baseline. Extra trial padding sits above the amount. On a phone the trial badge sits after the plan name. `config.layout` does not set density. Anything else raises `ArgumentError`. No database migration. No webhook change.

`CurrentPlanComponent` on `/billing` paints Trial with FlatPack badge `style: :primary` and the plan name with `PageTitle` `variant: :h2`. Current stays `style: :success`. The group name is muted `--text-xs` text above the plan name when more than one subscription type is configured. Status badges sit top-right. Relative timing from `current_period_end` sits in brackets after the price ("$29/month (Trial ends in 2 days)", "$29/month (Renews in 21 days)", or today). `/plans` cards stay `h3`. `stripe_card_stack` lays those card bodies out with FlatPack `Collection` (`as: :list`, `layout: :stack`, `gap: :md`). Admin pricing-card headings use `SectionTitle`. The `/plans` What’s included disclosure is FlatPack `Collapse` (`open: false`, `border: false`).

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
