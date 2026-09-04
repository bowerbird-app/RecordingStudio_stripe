# Dummy App

This Rails app proves Recording Studio Stripe in a host.

Sign in with `admin@admin.com` / `Password`.

## Routes

- `/` — current workspace plan, usage, and what the plan opens
- `/plans` — Products and Prices, left aligned, with a monthly/yearly toggle under each plan group name
- `/pricing` — the same plan cards, centered, no login
- `/billing` — one card per live plan group, usage percent, extra packs, and Manage billing on Stripe (Customer Portal)
- `/admin` — Stripe admin section. The Admin button switches to Studio Admin first, because Admin authorizes against that root.
- `/webhooks/stripe` — Stripe webhook intake
- `/users/sign_in` — Devise

Local mode (no `STRIPE_SECRET_KEY`) writes Customers and Subscriptions in the dummy database so you can click through. Dummy seeds Studio (Starter, Pro) and Inbox (Inbox, Inbox Plus). With keys, Checkout and webhooks talk to Stripe.

Authenticated pages use a dummy copy of Recording Studio `default_layout` with `html data-theme="rounded"`. Recording Studio puts that attribute on `body`, which does not override Flatpack `:root` tokens. Dummy `config/importmap.rb` pins Turbo and Recording Studio Admin screen controllers so product tables load.

Dummy registers `generate_image` and `export_csv` paywalls. Pro opens image generation. Inbox Plus opens CSV export. Home shows those as chips.
