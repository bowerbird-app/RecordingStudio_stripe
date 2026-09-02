# frozen_string_literal: true

module RecordingStudioStripe
  class Client
    def self.current
      configuration = RecordingStudioStripe.configuration
      return configuration.client if configuration.client

      if configuration.secret_key.present?
        return Stripe::StripeClient.new(configuration.secret_key,
                                        stripe_version: configuration.api_version)
      end

      raise MissingStripeKey, "Set STRIPE_SECRET_KEY or RecordingStudioStripe.configuration.secret_key"
    end
  end
end
