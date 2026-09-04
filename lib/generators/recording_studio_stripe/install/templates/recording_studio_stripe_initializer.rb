# frozen_string_literal: true

RecordingStudioStripe.configure do |config|
  config.secret_key = ENV.fetch("STRIPE_SECRET_KEY", nil)
  config.publishable_key = ENV.fetch("STRIPE_PUBLISHABLE_KEY", nil)
  config.webhook_secret = ENV.fetch("STRIPE_WEBHOOK_SECRET", nil)
  # Named usage counters. Defaults are ai_tokens and api_calls.
  # Add your own, then set included_<name> on each plan Price.
  # config.meters = {
  #   "ai_tokens" => { "label" => "AI tokens" },
  #   "api_calls" => { "label" => "API calls" }
  # }
  # Named plan features. Tick them on a Product in Admin.
  # Check with RecordingStudioAccessible.authorized_action?(action: :generate_image, recording: root)
  # config.paywalls = {
  #   "generate_image" => { "label" => "Generate an image" },
  #   "export_csv" => { "label" => "Export CSV" }
  # }
  # Optional. Omit this to keep one live plan per workspace.
  # Each plan Product belongs to one type. A workspace can hold one live plan per type.
  # config.subscription_types = {
  #   "press_kits" => { "label" => "Press kits" },
  #   "media_monitoring" => { "label" => "Media monitoring" }
  # }
end
