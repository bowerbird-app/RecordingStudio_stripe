# frozen_string_literal: true

module RecordingStudioStripe
  class PlansController < ApplicationController
    before_action :authorize_view!

    def index
      @interval = params[:interval].presence_in(%w[month year]) || "month"
      @products = Catalog.plan_products
      @current_subscription = billing.subscription
    end
  end
end
