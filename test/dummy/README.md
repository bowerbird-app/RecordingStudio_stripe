# Dummy App

This Rails app proves Recording Studio Stripe in a host.

Sign in with `admin@admin.com` / `Password`.

Dummy credentials (`config/credentials.yml.enc`) use the shared RecordingStudio_* development master key. Set `RAILS_MASTER_KEY`, or write that key to `config/master.key` (gitignored). Do not mint a per-repo dummy key. Confirm decrypt with `bin/rails credentials:show`. Stripe keys stay in environment variables.

## Routes

- `/` — current workspace on Flatpack’s sidebar shell. Pricing, billing, and usage live on their own pages
- `/press_kits` — list and add press kits for the workspace
- `/plans` — Products and Prices, titled Pricing, centered, with the dummy backdrop `/plans-backdrop.svg` in the default layout background slot, and an interval toggle under each plan group name when dummy seeds more than one type. A pill appears only when that group has a Price for it. Pass `intervals:` to keep the page on a shorter list. Upgrade and Downgrade open a confirmation page first
- `/pricing` — the same cards, centered title, subtitle, and interval pills, no login
- `/billing` — one card per live plan group, and Manage billing on Stripe (Customer Portal). See usage only when a live plan has recorded cap or meter use
- `/billing/usage` — one full-width card per standing cap or period meter. Breakdown appears when extra packs add to a meter.
- `/admin` — Stripe admin section. The Admin button switches to Studio Admin first, because Admin authorizes against that root.
- `/webhooks/stripe` — Stripe webhook intake
- `/users/sign_in` — Devise

Local mode (no `STRIPE_SECRET_KEY`) writes Customers and Subscriptions in the dummy database so you can click through. Dummy seeds Studio (Starter, Pro, Team) and Inbox (Inbox, Inbox Plus, Inbox Pro). Each plan has a monthly Price and a yearly Price. Dummy does not seed a weekly Price. Pro also has a $1, 14-day trial. With keys, Checkout and webhooks talk to Stripe.

Dummy home uses Flatpack `SidebarLayout` with `html data-theme="rounded"`. `/plans`, `/billing`, `/billing/usage`, and the docs pages use Recording Studio `default_layout`. That layout sets `html data-theme="rounded"` and reads `content_for :background_image` and `content_for :page_width`. Close on those billing pages is `flat_pack_page_nav` `anchor_href` on the engine views. `/pricing` uses the public layout. Dummy `config/importmap.rb` pins Turbo and Recording Studio Admin screen controllers so product tables load.

Dummy registers `generate_image` and `export_csv` paywalls. Pro and Team open image generation. Inbox Plus and Inbox Pro open CSV export. Staff tick those on the Product in Admin.

Dummy also registers a `press_kits` standing limit on Studio plans. Starter includes 3. Pro includes 10. Team includes 25. `/billing/usage` shows how many you can keep as `used/included` above the bar. `/press_kits` lists them and adds more. Creating past the cap sends you to `/plans`. Plan cards on `/plans` and `/pricing` list those caps, included usage, and ticked features, with icons from the initializer. Team also shows a display-only line. Hide or reorder lines on the Product in Admin. Pro's card strikes $29/mo, shows $1 trial, a 14 day trial badge, and Try now until that workspace already has a Studio plan. Each seeded plan also has a subtitle under its name, such as "For the usual week" on Pro. Staff change that line next to the name on the plan form.
