# frozen_string_literal: true

RecordingStudioStripe.configure do |config|
  config.secret_key = ENV["STRIPE_SECRET_KEY"]
  config.publishable_key = ENV["STRIPE_PUBLISHABLE_KEY"]
  config.webhook_secret = ENV["STRIPE_WEBHOOK_SECRET"]
  # Named usage counters. Defaults are ai_tokens and api_calls.
  # Add your own, then set included_<name> on each plan Price.
  # icon and plan_line are for the public plan card. %{quantity} is shortened (1m, 10k).
  config.meters = {
    "ai_tokens" => { "label" => "AI tokens", "icon" => "sparkles" },
    "api_calls" => { "label" => "API calls", "icon" => "bolt" }
  }
  # Named plan features. Tick them on a Product in Admin.
  # Check with RecordingStudioAccessible.authorized_action?(action: :generate_image, recording: root)
  config.paywalls = {
    "generate_image" => { "label" => "Generate an image", "icon" => "photo" },
    "export_csv" => { "label" => "Export CSV", "icon" => "table-cells" }
  }
  config.subscription_types = {
    "studio" => { "label" => "Studio" },
    "inbox" => { "label" => "Inbox" }
  }
  # Standing caps for how many of a type can exist under the workspace.
  # The number lives on the Product. Missing or 0 means none on that plan.
  config.limits = {
    "press_kits" => {
      "label" => "Press kits",
      "recordable_type" => "PressKit",
      "subscription_type" => "studio",
      "icon" => "rectangle-stack",
      "plan_line" => "%{quantity} press kits"
    }
  }
end
