Recording Studio Stripe is mounted.

1. Set STRIPE_SECRET_KEY, or leave it blank for local dummy checkout. Do not deploy local mode publicly.
2. Include RecordingStudioStripe::Billable on the workspace root.
3. Run `bin/rails generate recording_studio_stripe:migrations` then `db:migrate`.
4. Rebuild Tailwind if you use it.
5. Plans live at /plans. Billing lives at the mount path. Webhooks at /webhooks/stripe.
6. Grant Accessible :admin on the workspace for anyone who should pay.
7. Optional: set config.subscription_types so a workspace can hold one live plan per group.
8. Optional: set config.limits so a plan can cap how many of a type exist. Put the number on the Product.
9. Optional: set config.current_actor and config.current_root_recording if those helpers are not already on the host.
