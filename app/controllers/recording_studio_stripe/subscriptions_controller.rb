# frozen_string_literal: true

module RecordingStudioStripe
  class SubscriptionsController < ApplicationController
    before_action :authorize_admin!

    def edit
      @change = RecordingStudioStripe::PlanChange.build(
        root_recording: current_billing_root,
        price_id: params[:price_id]
      )
      return if @change

      redirect_to recording_studio_stripe.engine_plans_path, alert: "Pick a plan from the list."
    end

    def update
      price = Price.active.includes(:product).find_by(id: params[:price_id])
      unless price&.product&.plan? && price.recurring?
        redirect_to recording_studio_stripe.engine_plans_path, alert: "Pick a plan from the list."
        return
      end

      ChangePlan.call(root_recording: current_billing_root, price: price, actor: current_actor)
      redirect_to recording_studio_stripe.root_path, notice: plan_change_notice(price)
    rescue NoSubscription, InvalidPrice => e
      redirect_to recording_studio_stripe.engine_plans_path, alert: e.message
    end

    def destroy
      CancelSubscription.call(
        root_recording: current_billing_root,
        subscription_type: params[:subscription_type]
      )
      redirect_to recording_studio_stripe.root_path, notice: "This plan stays on until the period ends."
    rescue NoSubscription => e
      redirect_to recording_studio_stripe.root_path, alert: e.message
    end

    def resume
      ResumeSubscription.call(
        root_recording: current_billing_root,
        subscription_type: params[:subscription_type]
      )
      redirect_to recording_studio_stripe.root_path, notice: "Nice. Billing keeps going."
    rescue NoSubscription => e
      redirect_to recording_studio_stripe.root_path, alert: e.message
    end

    private

    def plan_change_notice(price)
      type = SubscriptionTypes.normalize(price.product&.subscription_type)
      subscription = billing.line(type).subscription
      if subscription&.scheduled_price_id == price.id
        "We’ll switch you at the next renewal."
      elsif subscription&.price_id == price.id
        "You’re on the new plan."
      else
        "Stripe is confirming this plan. Refresh in a moment."
      end
    end
  end
end
