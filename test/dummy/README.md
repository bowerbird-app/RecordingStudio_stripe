# Dummy App

This Rails app proves Recording Studio Stripe in a host.

Sign in with `admin@admin.com` / `Password`.

## Routes

- `/` — current workspace plan and usage
- `/plans` — Products and Prices
- `/billing` — usage remaining and extra packs
- `/admin` — Stripe admin section. The Admin button switches to Studio Admin first, because Admin authorizes against that root.
- `/webhooks/stripe` — Stripe webhook intake
- `/users/sign_in` — Devise

Local mode (no `STRIPE_SECRET_KEY`) writes Customers and Subscriptions in the dummy database so you can click through. With keys, Checkout and webhooks talk to Stripe.

Authenticated pages use a dummy copy of Recording Studio `default_layout` with `html data-theme="rounded"`. Recording Studio puts that attribute on `body`, which does not override Flatpack `:root` tokens. Dummy `config/importmap.rb` pins Turbo and Recording Studio Admin screen controllers so product tables load.
