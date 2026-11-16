Recording Studio Stripe is mounted.

1. Set STRIPE_SECRET_KEY and STRIPE_WEBHOOK_SECRET for live checkout and signed webhooks. The app still boots, migrates, and builds assets when they are blank. See the table below. Set RECORDING_STUDIO_STRIPE_REQUIRE_SECRETS=1 to raise on a production boot that is missing the secret key or the webhook secret.
2. Include RecordingStudioStripe::Billable on the workspace root.
3. Run `bin/rails generate recording_studio_stripe:migrations` then `db:migrate`.
4. Rebuild Tailwind if you use it.
5. If your layout does not yield :head, link recording_studio_stripe/button after Flatpack.
6. Pricing lives at /plans. Billing lives at the mount path. Usage at {mount}/usage. Webhooks at /webhooks/stripe.
7. Grant Accessible :admin on the workspace for anyone who should pay.
8. Optional: set config.subscription_types so a workspace can hold one live plan per group.
9. Optional: set config.limits so a plan can cap how many of a type exist. Put the number on the Product.
10. Optional: set icon and plan_line on limits, meters, and paywalls for the public plan card.
11. Optional: set config.current_actor and config.current_root_recording if those helpers are not already on the host.
12. Set config.site_admin_recording for Stripe Admin forms. Missing or nil denies those screens.
13. Optional: set Trial days and Trial amount in cents on a plan Product for a paid or $0 trial.
14. Customer screens use `recording_studio.stripe.*`. The gem ships English. Add host locale files to translate. Staff Admin stays English.

## Running without keys

| Key | When it is missing | Status |
| --- | --- | --- |
| STRIPE_WEBHOOK_SECRET | Outside local mode, POST /webhooks/stripe returns before reading the body and stores nothing. A bad or missing signature stays 400 once the secret is set. | 503 |
| STRIPE_SECRET_KEY | Checkout, the portal, and admin sync raise NotConfigured at call time. HTML shows “Billing isn't set up”. JSON returns an error body. | 503 |
| STRIPE_PUBLISHABLE_KEY | Not used to boot, migrate, or build assets. | none |

`config.require_secrets` defaults to false. `RECORDING_STUDIO_STRIPE_REQUIRE_SECRETS=1` turns it on. Production then raises MissingWebhookSecret or MissingStripeKey. Asset tasks and `tailwindcss:build` / `tailwindcss:watch` still skip that raise.
