# Dummy App

This Rails app proves Recording Studio Stripe in a host.

Sign in with `admin@admin.com` / `Password`.

## Routes

- `/` — current workspace on Flatpack’s sidebar shell. Plans and billing live on their own pages
- `/press_kits` — list and add press kits for the workspace
- `/plans` — Products and Prices, left aligned, with a monthly/yearly toggle under each plan group name when dummy seeds more than one type. Upgrade and Switch at renewal open a confirmation page first
- `/pricing` — the same plan cards, centered title and subtitle, no login
- `/billing` — one card per live plan group, usage percent, extra packs, and Manage billing on Stripe (Customer Portal)
- `/admin` — Stripe admin section. The Admin button switches to Studio Admin first, because Admin authorizes against that root.
- `/webhooks/stripe` — Stripe webhook intake
- `/users/sign_in` — Devise

Local mode (no `STRIPE_SECRET_KEY`) writes Customers and Subscriptions in the dummy database so you can click through. Dummy seeds Studio (Starter, Pro) and Inbox (Inbox, Inbox Plus). With keys, Checkout and webhooks talk to Stripe.

Dummy home uses Flatpack `SidebarLayout` with `html data-theme="rounded"`. Plans, billing, and docs stay on a dummy copy of Recording Studio `default_layout`. Recording Studio puts that theme attribute on `body`, which does not override Flatpack `:root` tokens, so the dummy copy sets it on `html`. The copy passes `page_nav_anchor_url` as Flatpack `anchor_href` so Close can leave `/plans` and `/billing` for home. Dummy `config/importmap.rb` pins Turbo and Recording Studio Admin screen controllers so product tables load.

Dummy registers `generate_image` and `export_csv` paywalls. Pro opens image generation. Inbox Plus opens CSV export. Staff tick those on the Product in Admin.

Dummy also registers a `press_kits` standing limit on Studio plans. Starter includes 3. Pro includes 10. `/billing` shows how many you can keep. `/press_kits` lists them and adds more. Creating past the cap sends you to `/plans`.
