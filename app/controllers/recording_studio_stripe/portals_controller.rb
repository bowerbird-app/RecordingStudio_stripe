# frozen_string_literal: true

module RecordingStudioStripe
  class PortalsController < ApplicationController
    before_action :authorize_edit!

    def create
      result = StartPortalSession.call(
        root_recording: current_billing_root,
        return_url: after_checkout_url
      )
      if result[:unavailable]
        redirect_to recording_studio_stripe.root_path,
                    alert: "Invoices and cards live in Stripe. Add keys to open them."
      else
        redirect_to result[:url], allow_other_host: true
      end
    rescue NoCustomer
      redirect_to recording_studio_stripe.root_path,
                  alert: "Pay once first, then invoices and cards show up here."
    rescue Stripe::StripeError
      redirect_to recording_studio_stripe.root_path,
                  alert: "Stripe could not open billing. Try again."
    end
  end
end
