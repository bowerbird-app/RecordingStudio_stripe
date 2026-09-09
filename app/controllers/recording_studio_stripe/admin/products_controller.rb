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
          subscription_type: params[:subscription_type],
          limits: product_limits,
          plan_card: product_plan_card
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
          subscription_type: params[:subscription_type],
          limits: product_limits,
          plan_card: product_plan_card
        )
        redirect_to admin_screen_url("products"), notice: "#{@product.name} is saved."
      rescue InvalidPrice, ActiveRecord::RecordInvalid => e
        flash.now[:alert] = e.message
        @selected_paywall_names = Array(params[:paywall_names])
        render :edit, status: :unprocessable_entity
      end

      private

      def product_limits
        return {} unless Limits.configured?
        return {} unless params[:limits]

        params.require(:limits).permit(*Limits.keys).to_h
      end

      def product_plan_card
        return unless params[:plan_card]

        raw = params.require(:plan_card).permit(:order, hide: [], extras: %i[key text icon])
        {
          "hide" => Array(raw[:hide]).reject(&:blank?),
          "order" => plan_card_order(raw[:order]),
          "extras" => plan_card_extras(raw[:extras])
        }
      end

      def plan_card_order(value)
        rows = value.is_a?(Array) ? value : value.to_s.split(/\r?\n/)
        rows.map(&:strip).reject(&:blank?)
      end

      def plan_card_extras(raw)
        rows = case raw
               when ActionController::Parameters, Hash
                 raw.to_h.values
               else
                 Array(raw)
               end
        rows.filter_map do |extra|
          row = extra.to_h.stringify_keys
          text = row["text"].to_s.strip
          next if text.blank?

          {
            "key" => row["key"].to_s.strip.presence || text.parameterize(separator: "_"),
            "text" => text,
            "icon" => row["icon"].to_s.strip.presence
          }.compact
        end
      end
    end
  end
end
