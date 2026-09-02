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
end
