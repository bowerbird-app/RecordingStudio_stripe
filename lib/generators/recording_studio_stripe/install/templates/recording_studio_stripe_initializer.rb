# frozen_string_literal: true

RecordingStudioStripe.configure do |config|
  config.secret_key = ENV.fetch("STRIPE_SECRET_KEY", nil)
  config.publishable_key = ENV.fetch("STRIPE_PUBLISHABLE_KEY", nil)
  config.webhook_secret = ENV.fetch("STRIPE_WEBHOOK_SECRET", nil)
  # Required when secret_key is set. Unsigned webhooks only work in local mode.
  # Named usage counters. Defaults are ai_tokens and api_calls.
  # Add your own, then set included_<name> on each plan Price.
  # icon and plan_line are for the public plan card. %{quantity} is shortened (1m, 10k).
  # config.meters = {
  #   "ai_tokens" => {
  #     "label" => "AI tokens",
  #     "icon" => "sparkles",
  #     "plan_line" => "%{quantity} AI tokens each period"
  #   },
  #   "api_calls" => { "label" => "API calls", "icon" => "bolt" }
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
  #   "inbox" => { "label" => "Inbox" }
  # }
  # Standing caps for how many of a type can exist under the workspace.
  # The number lives on the Product. Missing or 0 means none on that plan.
  # Do not reuse a plan group name as a limit name unless they are the same thing.
  # config.limits = {
  #   "press_kits" => {
  #     "label" => "Press kits",
  #     "recordable_type" => "PressKit",
  #     "subscription_type" => "studio",
  #     "icon" => "rectangle-stack",
  #     "plan_line" => "%{quantity} press kits"
  #   }
  # }
  # config.limit_reached_path = "/plans"
  # config.automatic_tax = true
  # config.allow_promotion_codes = true
end
