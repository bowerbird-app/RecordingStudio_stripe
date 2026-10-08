# frozen_string_literal: true

module RecordingStudioStripe
  class PortalsController < ApplicationController
    before_action :authorize_admin!

    def create
      result = StartPortalSession.call(
        root_recording: current_billing_root,
        return_url: after_checkout_url
      )
      if result[:unavailable]
        redirect_to recording_studio_stripe.root_path,
                    alert: Copy.t("alerts.portal_needs_keys")
      else
        redirect_to result[:url], allow_other_host: true
      end
    rescue NoCustomer
      redirect_to recording_studio_stripe.root_path,
                  alert: Copy.t("alerts.portal_needs_pay")
    rescue Stripe::StripeError
      redirect_to recording_studio_stripe.root_path,
                  alert: Copy.t("alerts.portal_failed")
    end
  end
end
