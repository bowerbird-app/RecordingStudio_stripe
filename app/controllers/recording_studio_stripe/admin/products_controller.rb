# frozen_string_literal: true

module RecordingStudioStripe
  module Admin
    class ProductsController < BaseController
      def new
        @kind = params[:kind].presence_in(Product::KINDS) || "plan"
        @selected_paywall_names = Array(params[:paywall_names])
      end

      def create
        product = CreateProduct.call(
          name: params.require(:name),
          kind: params.require(:kind),
          description: params[:description],
          paywall_names: Array(params[:paywall_names]),
          subscription_type: params[:subscription_type]
        )
        redirect_to admin_screen_url("products"), notice: "#{product.name} is on the catalogue."
      rescue InvalidPrice, ActiveRecord::RecordInvalid => e
        flash.now[:alert] = e.message
        @kind = params[:kind]
        @selected_paywall_names = Array(params[:paywall_names])
        render :new, status: :unprocessable_entity
      end

      def edit
        @product = Product.find(params[:id])
        @selected_paywall_names = @product.paywalls.map(&:name)
      end

      def update
        @product = Product.find(params[:id])
        UpdateProduct.call(
          product: @product,
          name: params.require(:name),
          description: params[:description],
          paywall_names: Array(params[:paywall_names]),
          subscription_type: params[:subscription_type]
        )
        redirect_to admin_screen_url("products"), notice: "#{@product.name} is saved."
      rescue InvalidPrice, ActiveRecord::RecordInvalid => e
        flash.now[:alert] = e.message
        @selected_paywall_names = Array(params[:paywall_names])
        render :edit, status: :unprocessable_entity
      end
    end
  end
end
