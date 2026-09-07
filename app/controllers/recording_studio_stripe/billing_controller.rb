# frozen_string_literal: true

module RecordingStudioStripe
  class BillingController < ApplicationController
    before_action :authorize_view!

    def show
      @lines = billing.active_lines
      @allowance_prices = Catalog.allowance_prices
      @show_manage_billing = show_manage_billing?
      @confirming_checkout = confirming_checkout?
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

    def confirming_checkout?
      params[:checkout].to_s == "ok" && !billing.subscribed?
    end
  end
end
