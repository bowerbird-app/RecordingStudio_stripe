# frozen_string_literal: true

module RecordingStudioStripe
  class AllowancesController < ApplicationController
    before_action :authorize_admin!

    def create
      price = Price.active.includes(:product).find_by(id: params[:price_id])
      unless price&.product&.allowance?
        redirect_to recording_studio_stripe.root_path, alert: "Pick an extra pack from billing."
        return
      end

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
