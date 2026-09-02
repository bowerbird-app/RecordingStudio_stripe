# frozen_string_literal: true

RecordingStudioStripe.configure do |config|
  config.secret_key = ENV["STRIPE_SECRET_KEY"]
  config.publishable_key = ENV["STRIPE_PUBLISHABLE_KEY"]
  config.webhook_secret = ENV["STRIPE_WEBHOOK_SECRET"]
  # Named usage counters. Defaults are ai_tokens and api_calls.
  # Add your own, then set included_<name> on each plan Price.
  # config.meters = {
  #   "ai_tokens" => { "label" => "AI tokens" },
  #   "api_calls" => { "label" => "API calls" }
  # }
end
