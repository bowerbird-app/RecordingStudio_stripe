# frozen_string_literal: true

module RecordingStudioStripe
  class BillingController < ApplicationController
    before_action :authorize_view!

    def show
      @subscription = billing.subscription
      @meters = Meter.order(:name).map { |meter| billing.meter(meter.name) }
      @allowance_prices = Catalog.allowance_prices
      @show_manage_billing = show_manage_billing?
    end

    private

    def show_manage_billing?
      return false unless billing.customer
      return true unless defined?(RecordingStudioAccessible)

      RecordingStudioAccessible.authorized?(
        actor: current_actor,
        recording: current_billing_root,
        role: :edit
      )
    end
  end
end
