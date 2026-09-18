Recording Studio Stripe is mounted.

1. Set STRIPE_SECRET_KEY, or leave it blank for local dummy checkout. Do not deploy local mode publicly.
2. Include RecordingStudioStripe::Billable on the workspace root.
3. Run `bin/rails generate recording_studio_stripe:migrations` then `db:migrate`.
4. Rebuild Tailwind if you use it.
5. If your layout does not yield :head, link recording_studio_stripe/button after Flatpack.
6. Plans live at /plans. Billing lives at the mount path. Usage at {mount}/usage. Webhooks at /webhooks/stripe.
7. Grant Accessible :admin on the workspace for anyone who should pay.
8. Optional: set config.subscription_types so a workspace can hold one live plan per group.
9. Optional: set config.limits so a plan can cap how many of a type exist. Put the number on the Product.
10. Optional: set icon and plan_line on limits, meters, and paywalls for the public plan card.
11. Optional: set config.current_actor and config.current_root_recording if those helpers are not already on the host.
