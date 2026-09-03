# frozen_string_literal: true

class PricingController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    @interval = params[:interval].presence_in(%w[month year]) || "month"
    @products = RecordingStudioStripe::Catalog.plan_products
  end

  private

  def application_layout
    "public"
  end
end
