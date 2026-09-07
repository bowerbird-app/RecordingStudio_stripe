===============================================================================

Recording Studio Stripe is in.

draw_recording_studio_stripe mounted billing at /billing, plans at /plans, and Stripe webhooks at /webhooks/stripe.

Include RecordingStudioStripe::Billable on your workspace root.

Copy migrations:

  bin/rails generate recording_studio_stripe:migrations
  bin/rails db:migrate

Staff admin: include RecordingStudioStripe::AdminSupport on the admin root and mount Recording Studio Admin.

Grant Accessible :admin on the workspace for anyone who should pay.

draw_recording_studio_stripe at: is the mount path.

If you use Tailwind, rebuild:

  bin/rails tailwindcss:build

===============================================================================
