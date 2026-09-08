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

      if live_plan?(price)
        redirect_to recording_studio_stripe.subscription_change_path(price_id: price.id)
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

    def live_plan?(price)
      Subscription.current_for(
        root_recording_id: current_billing_root.id,
        subscription_type: SubscriptionTypes.normalize(price.product&.subscription_type)
      )&.active?
    end
  end
end
