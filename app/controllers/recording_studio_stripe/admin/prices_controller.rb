# frozen_string_literal: true

module RecordingStudioStripe
  module Admin
    class PricesController < BaseController
      def new
        @product = Product.find(params[:product_id])
      end

      def create
        product = Product.find(params.require(:product_id))
        CreatePrice.call(
          product: product,
          unit_amount: params.require(:unit_amount),
          currency: params[:currency].presence || "usd",
          interval: params[:interval],
          metadata: price_metadata
        )
        redirect_to admin_screen_url("prices"), notice: "Price is live."
      rescue InvalidPrice, ActiveRecord::RecordInvalid => e
        @product = Product.find_by(id: params[:product_id])
        flash.now[:alert] = e.message
        render :new, status: :unprocessable_entity
      end

      private

      def price_metadata
        metadata = {}
        Meter.order(:name).each do |meter|
          value = params.dig(:included, meter.name)
          metadata["included_#{meter.name}"] = value if value.present?
        end
        metadata["meter"] = params[:meter] if params[:meter].present?
        metadata["allowance"] = params[:allowance] if params[:allowance].present?
        metadata
      end
    end
  end
end
