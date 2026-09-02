# frozen_string_literal: true

module RecordingStudioStripe
  class AllowancesController < ApplicationController
    before_action :authorize_edit!

    def create
      price = Price.active.find(params[:price_id])
      result = StartCheckout.call(
        root_recording: current_billing_root,
        price: price,
        actor: current_actor,
        success_url: "#{after_checkout_url}?allowance=ok",
        cancel_url: after_checkout_url
      )
      redirect_to result[:url], allow_other_host: true
    rescue InvalidPrice => e
      redirect_to recording_studio_stripe.root_path, alert: e.message
    end
  end
end
