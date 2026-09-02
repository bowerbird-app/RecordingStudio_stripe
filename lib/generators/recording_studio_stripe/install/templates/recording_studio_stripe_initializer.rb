# frozen_string_literal: true

RecordingStudioStripe.configure do |config|
  config.secret_key = ENV.fetch("STRIPE_SECRET_KEY", nil)
  config.publishable_key = ENV.fetch("STRIPE_PUBLISHABLE_KEY", nil)
  config.webhook_secret = ENV.fetch("STRIPE_WEBHOOK_SECRET", nil)
end
