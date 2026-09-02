# frozen_string_literal: true

RecordingStudioStripe.configure do |config|
  config.secret_key = ENV["STRIPE_SECRET_KEY"]
  config.publishable_key = ENV["STRIPE_PUBLISHABLE_KEY"]
  config.webhook_secret = ENV["STRIPE_WEBHOOK_SECRET"]
end
