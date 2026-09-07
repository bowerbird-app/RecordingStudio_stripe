# frozen_string_literal: true

module RecordingStudioStripe
  class CheckoutsController < ApplicationController
    before_action :authorize_admin!

    def create
      price = saleable_price
      unless price&.product&.plan? && price.recurring?
        redirect_to recording_studio_stripe.engine_plans_path, alert: "Pick a plan from the list."
        return
      end

      result = StartCheckout.call(
        root_recording: current_billing_root,
        price: price,
        actor: current_actor,
        success_url: "#{after_checkout_url}?checkout=ok",
        cancel_url: checkout_cancel_url
      )
      redirect_to result[:url], allow_other_host: true
    rescue InvalidPrice => e
      redirect_to recording_studio_stripe.engine_plans_path, alert: e.message
    end

    private

    def saleable_price
      Price.active.includes(:product).find_by(id: params[:price_id])
    end
  end
end
