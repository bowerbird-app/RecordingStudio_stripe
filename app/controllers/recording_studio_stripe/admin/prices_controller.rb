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

      def edit
        @price = Price.find(params[:id])
        @product = @price.product
      end

      def update
        @price = Price.find(params[:id])
        @product = @price.product
        UpdatePrice.call(price: @price, metadata: price_metadata)
        redirect_to admin_screen_url("prices"), notice: "Included amounts are saved."
      rescue InvalidPrice, ActiveRecord::RecordInvalid => e
        flash.now[:alert] = e.message
        render :edit, status: :unprocessable_entity
      end

      private

      def price_metadata
        metadata = {}
        Meter.order(:name).each do |meter|
          next unless included_params&.key?(meter.name)

          metadata["included_#{meter.name}"] = included_params[meter.name].to_s
        end
        metadata["meter"] = params[:meter] if params.key?(:meter)
        metadata["allowance"] = params[:allowance] if params.key?(:allowance)
        metadata
      end

      def included_params
        raw = params[:included]
        return unless raw.respond_to?(:to_unsafe_h) || raw.is_a?(Hash)

        raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h.stringify_keys : raw.stringify_keys
      end
    end
  end
end
