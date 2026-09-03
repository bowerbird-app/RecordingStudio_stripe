# frozen_string_literal: true

RecordingStudioStripe.configure do |config|
  config.secret_key = RecordingStudioStripe::Configuration.env_secret_key
  config.publishable_key = RecordingStudioStripe::Configuration.env_publishable_key
  config.webhook_secret = RecordingStudioStripe::Configuration.env_webhook_secret
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
end
