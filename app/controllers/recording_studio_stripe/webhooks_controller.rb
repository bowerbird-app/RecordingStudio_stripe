# frozen_string_literal: true

module RecordingStudioStripe
  class WebhooksController < ActionController::Base
    skip_forgery_protection

    def create
      result = ProcessWebhook.call(payload: request.body.read, signature: request.env["HTTP_STRIPE_SIGNATURE"])
      if result == :deferred
        head :service_unavailable
      else
        head :ok
      end
    rescue JSON::ParserError, Stripe::SignatureVerificationError
      head :bad_request
    end
  end
end
