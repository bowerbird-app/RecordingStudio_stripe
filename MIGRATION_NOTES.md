# Migration Notes

## Current Requirements

- Ruby 3.3 or newer
- Rails 8.1 or newer
- Recording Studio `>= 6.2.0` (gemspec). Development pin is GitHub tag `v6.2.0`
- Accessible `~> 0.22` (GitHub tag `v0.22.0`)
- `view_component` `>= 4.14, < 5` (this repo locks `4.19.0`)
- FlatPack `>= 0.1.315` through Recording Studio. This repo pins commit `1fcbafe94f8eb118f0a22182f63f5110fcc97a56` so the loaded version is `0.1.319`
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

Page titles use `content_for :title` and `content_for :subtitle`. Back and close use `flat_pack_page_nav`. The right side of the top nav uses `register_page_nav` or `content_for :page_nav_right`.

`recording_studio_background_image(url)` writes `content_for :background_image`. The default layout passes that URL to `FlatPack::PageLayout` as a decorative image (`alt=""`, `loading="lazy"`). A blank URL leaves the page unchanged. `recording_studio_page_width(:wide)` writes `content_for :page_width`. Allowed values are `:narrow`, `:default`, `:wide`, and `:full`. A blank value stays `:default`. A host layout that replaces the default reads both slots.

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
