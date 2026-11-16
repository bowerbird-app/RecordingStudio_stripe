# frozen_string_literal: true

module RecordingStudioStripe
  # Reports missing Stripe keys once at boot. Does not raise unless
  # config.require_secrets is on, and never during an asset or Tailwind build.
  module WebhookSecret
    MISSING_EFFECTS = {
      "STRIPE_WEBHOOK_SECRET" => "/webhooks/stripe returns 503",
      "STRIPE_SECRET_KEY" => "checkout/portal/admin sync disabled"
    }.freeze

    ASSET_TASK = /
      (?:^|:)
      (?:
        assets:(?:precompile|clean|clobber)
        |
        tailwindcss:(?:build|watch)
      )
      \b
    /x

    module_function

    def report!
      return if asset_build?

      enforce_strict! if RecordingStudioStripe.configuration.require_secrets
      warn_once!
    end

    def asset_build?
      return true if ENV["SECRET_KEY_BASE_DUMMY"].present?
      return false unless defined?(Rake) && Rake.respond_to?(:application)

      Array(Rake.application&.top_level_tasks).any? { |name| ASSET_TASK.match?(name.to_s) }
    end

    def enforce_strict!
      return unless Rails.env.production?

      missing = RecordingStudioStripe.configuration.missing_secrets
      raise MissingWebhookSecret, "Set STRIPE_WEBHOOK_SECRET in production" if missing.include?("STRIPE_WEBHOOK_SECRET")
      return unless missing.include?("STRIPE_SECRET_KEY")

      raise MissingStripeKey, "Set STRIPE_SECRET_KEY in production"
    end

    def warn_once!
      return if reported?

      message = warning_message
      return if message.nil?

      @reported = true
      Rails.logger.warn("[recording_studio_stripe] #{message}")
    end

    def warning_message
      configuration = RecordingStudioStripe.configuration
      return if configuration.local_mode?

      parts = configuration.missing_secrets.filter_map do |name|
        effect = MISSING_EFFECTS[name]
        "#{name} missing: #{effect}" if effect
      end
      return if parts.empty?

      parts.join("; ")
    end

    def reported?
      @reported == true
    end
  end
end
