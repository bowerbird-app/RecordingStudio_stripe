# frozen_string_literal: true

module RecordingStudioStripe
  class SubscriptionsController < ApplicationController
    before_action :authorize_edit!

    def update
      price = Price.active.find(params[:price_id])
      ChangePlan.call(root_recording: current_billing_root, price: price, actor: current_actor)
      redirect_to recording_studio_stripe.root_path, notice: plan_change_notice(price)
    rescue NoSubscription, InvalidPrice => e
      redirect_to recording_studio_stripe.engine_plans_path, alert: e.message
    end

    def destroy
      CancelSubscription.call(root_recording: current_billing_root)
      redirect_to recording_studio_stripe.root_path, notice: "This plan stays on until the period ends."
    rescue NoSubscription => e
      redirect_to recording_studio_stripe.root_path, alert: e.message
    end

    def resume
      ResumeSubscription.call(root_recording: current_billing_root)
      redirect_to recording_studio_stripe.root_path, notice: "Nice. Billing keeps going."
    rescue NoSubscription => e
      redirect_to recording_studio_stripe.root_path, alert: e.message
    end

    private

    def plan_change_notice(price)
      subscription = billing.subscription
      if subscription&.scheduled_price_id == price.id
        "We’ll switch you at the next renewal."
      else
        "You’re on the new plan."
      end
    end
  end
end
