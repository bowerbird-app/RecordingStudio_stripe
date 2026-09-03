Recording Studio Stripe is mounted.

1. Set STRIPE_SECRET_KEY (or Stripe_secret_key), or leave it blank for local dummy checkout.
2. Include RecordingStudioStripe::Billable on the workspace root.
3. Run `bin/rails generate recording_studio_stripe:migrations` then `db:migrate`.
4. Rebuild Tailwind if you use it.
5. Plans live at /plans. Billing lives at the mount path. Webhooks at /webhooks/stripe.
