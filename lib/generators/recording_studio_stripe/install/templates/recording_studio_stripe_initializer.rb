# frozen_string_literal: true

RecordingStudioStripe.configure do |config|
  config.secret_key = ENV.fetch("STRIPE_SECRET_KEY", nil)
  config.publishable_key = ENV.fetch("STRIPE_PUBLISHABLE_KEY", nil)
  config.webhook_secret = ENV.fetch("STRIPE_WEBHOOK_SECRET", nil)
  # Production raises on boot when this is blank. Unsigned webhooks are accepted
  # only in development or test local mode: no Stripe key, no client, and no webhook secret.
  # Named usage counters. Defaults are ai_tokens and api_calls.
  # Add your own, then set included_<name> on each plan Price.
  # icon and plan_line are for the public plan card. %{quantity} is shortened (1m, 10k).
  # config.meters = {
  #   "ai_tokens" => {
  #     "label" => "AI tokens",
  #     "icon" => "sparkles",
  #     "plan_line" => "%{quantity} AI tokens each period"
  #   },
  #   "api_calls" => { "label" => "API calls", "icon" => "bolt" },
  #   "credits" => {
  #     "label" => "Credits",
  #     "icon" => "sparkles",
  #     "plan_line" => "%{quantity} credits each period"
  #   }
  # }
  # config.usage_costs = {
  #   "ai.jev" => 1,
  #   "web.brave" => 5
  # }
  # Named plan features. Tick them on a Product in Admin.
  # Check with RecordingStudioAccessible.authorized_action?(action: :generate_image, recording: root)
  # config.paywalls = {
  #   "generate_image" => { "label" => "Generate an image", "icon" => "photo" },
  #   "export_csv" => { "label" => "Export CSV", "icon" => "table-cells" }
  # }
  # Optional. Omit this to keep one live plan per workspace.
  # Each plan Product belongs to one type. A workspace can hold one live plan per type.
  # config.subscription_types = {
  #   "studio" => { "label" => "Studio" },
  #   "inbox" => { "label" => "Inbox", "downgrade_timing" => "immediately" }
  # }
  # downgrade_timing is at_period_end (the default) or immediately.
  # at_period_end schedules a downgrade and cancels at period end.
  # immediately switches the Stripe Price now, with proration, and cancel ends the subscription now.
  # Standing caps. The number lives on the Product. Missing or 0 means none on that plan.
  # aggregation defaults to count: live recordings of recordable_type. No billing-period reset.
  # quantity is a current total. Register how to read it. Enforce it with with_capacity!.
  # per_item is a ceiling on one item. ceiling is nil when the plan omits limit_<name>.
  # no_plan_ceiling applies only with no live plan. Enforce it with enforce_item!.
  # Do not reuse a plan group name as a limit name unless they are the same thing.
  # config.limits = {
  #   "press_kits" => {
  #     "label" => "Press kits",
  #     "recordable_type" => "PressKit",
  #     "aggregation" => "count",
  #     "subscription_type" => "studio",
  #     "icon" => "rectangle-stack",
  #     "plan_line" => "%{quantity} press kits"
  #   },
  #   "storage_bytes" => {
  #     "label" => "Storage",
  #     "aggregation" => "quantity",
  #     "subscription_type" => "studio"
  #   },
  #   "max_file_bytes" => {
  #     "label" => "Max file size",
  #     "aggregation" => "per_item",
  #     "unit" => "bytes",
  #     "subscription_type" => "studio",
  #     "plan_line" => "Up to %{quantity} per file",
  #     "no_plan_ceiling" => 10.megabytes
  #   }
  # }
  # RecordingStudioStripe.register_limit_usage(:storage_bytes) do |root_recording|
  #   MyStorageGem.current_bytes_for(root_recording)
  # end
  # Decorative backdrop for /plans. Blank leaves that page unchanged.
  # config.plans_background_image = "/plans-backdrop.svg"
  # Required for Stripe Admin forms. Return the site-admin workspace recording
  # (or the admin root recordable). A zero-argument callable runs as instance_exec
  # on the controller. A callable may take controller or controller:. Missing or
  # nil denies those screens.
  # config.site_admin_recording = lambda {
  #   admin_root = AdminRoot.find_by(name: "Studio Admin")
  #   next unless admin_root
  #
  #   RecordingStudio.root_recording_for(admin_root)
  # }
  # config.limit_reached_path = "/plans"
  # config.usage_path = "/billing/usage"
  # config.automatic_tax = true
  # config.allow_promotion_codes = true
end
