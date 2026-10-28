# Recording Studio 6.2 layout

Customer and staff screens use the Recording Studio 6.2 default template.

- Gemspec requires `recording_studio` `>= 6.2.0`, Accessible `~> 0.22`, and `view_component` `>= 4.14, < 5`
- Development pins are Recording Studio `v6.2.0`, Accessible `v0.22.0`, Admin `v2.7.0`, Trashable `v0.12.0`, Logs `v0.7.0`, Root Switchable `8dd47257db449120496ad64ed2ce68af600dd6cd`, Metrics `v0.6.1`, Cache `v0.5.1`, Internationalization `v0.1.7`, and FlatPack tag `v0.1.327`
- `config.layout` is the engine layout setting. Controllers call `recording_studio_layout`
- Page titles are `content_for :title` and `content_for :subtitle`. Back and close use `flat_pack_page_nav`
- `/plans` centers the title and subtitle in `PlansComponent` (`align: :center`, `text-center` on the page title). It does not set `content_for :title`
- A blank `plans.subtitle` is not rendered. The gem English subtitle stays "Monthly or yearly. You can switch later." Dummy English uses that line. The plans heading and group headings use `fp-on-backdrop`, so the title and subtitle take the backdrop text colors when a layout photo is set. Cards stay outside that class
- Interval pills use a FlatPack track and `style: :primary`. The track fill is `--surface-background-color`, so the active pill and the idle pill both read clearly over a photo
- `recording_studio_background_image` writes `content_for :background_image`. `recording_studio_page_width` writes `content_for :page_width`. The default layout paints a decorative backdrop and sets `FlatPack::PageLayout` width. Blank values leave the page unchanged
- `/plans` passes `config.plans_background_image` to that helper. Nil leaves the page plain. Dummy sets `/plans-backdrop.svg`
- On a phone, plan cards are compact rows (name, price, button, then What’s included). A trial badge sits after the plan name. From the `md` breakpoint a group shares four subgrid rows. Amounts sit on one baseline. Extra trial padding sits above the amount. The button row pins Choose, Try, Current, and Upgrade to the top of the shared row. `density: :cards` keeps the tall card on a phone. `density: :rows` keeps the compact row at every width
- `test/support/widen_recording_studio_requirement.rb` lets Bundler resolve sibling gems that still declare Recording Studio below 6. The widened floor stays `>= 6.1.0`, which `6.2.0` satisfies
