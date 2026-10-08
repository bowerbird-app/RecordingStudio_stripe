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

      redirect_to recording_studio_stripe.engine_plans_path, alert: Copy.t("alerts.pick_plan")
    end

    def confirm_cancel
      @cancel = RecordingStudioStripe::CancelPlan.build(
        root_recording: current_billing_root,
        subscription_type: params[:subscription_type]
      )
      return if @cancel

      redirect_to recording_studio_stripe.root_path, alert: Copy.t("alerts.nothing_to_cancel")
    rescue NoSubscription => e
      redirect_to recording_studio_stripe.root_path, alert: e.message
    end

    def update
      price = Price.active.includes(:product).find_by(id: params[:price_id])
      unless price&.product&.plan? && price.recurring?
        redirect_to recording_studio_stripe.engine_plans_path, alert: Copy.t("alerts.pick_plan")
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
      redirect_to recording_studio_stripe.root_path, notice: Copy.t("notices.plan_stays_until_end")
    rescue NoSubscription => e
      redirect_to recording_studio_stripe.root_path, alert: e.message
    end

    def resume
      ResumeSubscription.call(
        root_recording: current_billing_root,
        subscription_type: params[:subscription_type]
      )
      redirect_to recording_studio_stripe.root_path, notice: Copy.t("notices.billing_keeps_going")
    rescue NoSubscription => e
      redirect_to recording_studio_stripe.root_path, alert: e.message
    end

    def keep
      ClearScheduledChange.call(
        root_recording: current_billing_root,
        subscription_type: params[:subscription_type]
      )
      redirect_to recording_studio_stripe.root_path, notice: Copy.t("notices.stay_on_plan")
    rescue NoSubscription => e
      redirect_to recording_studio_stripe.root_path, alert: e.message
    end

    private

    def plan_change_notice(price)
      type = SubscriptionTypes.normalize(price.product&.subscription_type)
      subscription = billing.line(type).subscription
      if subscription&.scheduled_price_id == price.id
        Copy.t("notices.switch_at_renewal")
      elsif subscription&.price_id == price.id
        Copy.t("notices.on_new_plan")
      else
        Copy.t("notices.stripe_confirming")
      end
    end
  end
end
