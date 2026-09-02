# frozen_string_literal: true

module RecordingStudioStripe
  class BillingController < ApplicationController
    before_action :authorize_view!

    def show
      @subscription = billing.subscription
      @meters = Meter.order(:name).map { |meter| billing.meter(meter.name) }
      @allowance_prices = Catalog.allowance_prices
    end
  end
end
