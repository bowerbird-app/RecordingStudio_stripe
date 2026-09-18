# frozen_string_literal: true

module RecordingStudioStripe
  class BillingController < ApplicationController
    before_action :authorize_view!

    def show
      @lines = billing.active_lines
      @show_manage_billing = show_manage_billing?
      @show_see_usage = show_see_usage?
      @confirming_checkout = confirming_checkout?
      @confirming_allowance = confirming_allowance?
      @waiting_on_stripe = waiting_on_stripe?
    end

    private

    def show_manage_billing?
      return false unless billing.customer
      return true unless defined?(RecordingStudioAccessible)

      RecordingStudioAccessible.authorized?(
        actor: current_actor,
        recording: current_billing_root,
        role: :admin
      )
    end

    def show_see_usage?
      helpers.usage_in_use?(billing)
    end

    def confirming_checkout?
      params[:checkout].to_s == "ok" && !billing.subscribed?
    end

    def confirming_allowance?
      params[:allowance].to_s == "ok"
    end

    def waiting_on_stripe?
      return true if confirming_checkout?

      Subscription.exists?(root_recording_id: current_billing_root.id, status: "incomplete") && !billing.subscribed?
    end
  end
end
