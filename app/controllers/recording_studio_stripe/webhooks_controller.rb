# frozen_string_literal: true

module RecordingStudioStripe
  class WebhooksController < ActionController::Base
    skip_forgery_protection

    def create
      return refuse_unsigned if webhook_secret_missing?

      result = ProcessWebhook.call(payload: request.body.read, signature: request.env["HTTP_STRIPE_SIGNATURE"])
      if result == :deferred
        head :service_unavailable
      else
        head :ok
      end
    rescue JSON::ParserError, Stripe::SignatureVerificationError
      head :bad_request
    end

    private

    def webhook_secret_missing?
      configuration = RecordingStudioStripe.configuration
      configuration.webhook_secret.blank? && !configuration.local_mode?
    end

    def refuse_unsigned
      Rails.logger.error(
        "[recording_studio_stripe] STRIPE_WEBHOOK_SECRET missing: /webhooks/stripe returns 503"
      )
      head :service_unavailable
    end
  end
end
