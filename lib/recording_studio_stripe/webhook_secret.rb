# frozen_string_literal: true

module RecordingStudioStripe
  module WebhookSecret
    module_function

    def require_in_production!
      return unless Rails.env.production?
      return if RecordingStudioStripe.configuration.webhook_secret.present?
      return if asset_build?

      raise MissingWebhookSecret, "Set STRIPE_WEBHOOK_SECRET in production"
    end

    def asset_build?
      return true if ENV["SECRET_KEY_BASE_DUMMY"].present?
      return false unless defined?(Rake) && Rake.respond_to?(:application)

      Array(Rake.application&.top_level_tasks).any? do |name|
        name.to_s.match?(/assets:(precompile|clean|clobber)\b/)
      end
    end
  end
end
