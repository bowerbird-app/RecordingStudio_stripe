# frozen_string_literal: true

module RecordingStudioStripe
  class Trial
    FEE_KIND = "trial_fee"

    def self.for(product)
      new(product)
    end

    def initialize(product)
      @product = product
    end

    def offered?
      days.positive?
    end

    def days
      positive_int(metadata["trial_days"])
    end

    def unit_amount
      nonnegative_int(metadata["trial_unit_amount"])
    end

    def fee_price
      fee_prices.find(&:active?)
    end

    def checkout_label
      return "Start trial" unless offered? && unit_amount.positive?

      "Try for #{formatted_amount}"
    end

    def apply_to_checkout(params, plan_price:)
      return params unless offered?

      params[:line_items] = checkout_line_items(plan_price)
      params[:payment_method_collection] = "always"
      (params[:subscription_data] ||= {})[:trial_period_days] = days
      params
    end

    def local_subscription_attrs
      return {} unless offered?

      { status: "trialing", current_period_end: Time.current + days.days }
    end

    def fee_prices
      Array(price_records).select { |price| fee_kind?(price) }
    end

    private

    def checkout_line_items(plan_price)
      items = [{ price: plan_price.stripe_id, quantity: 1 }]
      items << { price: fee_price.stripe_id, quantity: 1 } if charge_fee?
      items
    end

    def charge_fee?
      unit_amount.positive? && fee_price.present?
    end

    def currency
      fee_price&.currency.presence || "usd"
    end

    def formatted_amount
      Price.formatted_amount(unit_amount, currency)
    end

    def metadata
      (@product&.metadata || {}).to_h.stringify_keys
    end

    def price_records
      return [] unless @product.respond_to?(:prices)

      prices = @product.prices
      return [] if prices.nil?
      return prices.one_time if prices.respond_to?(:one_time)

      Array(prices)
    end

    def fee_kind?(price)
      price.metadata.to_h.stringify_keys["kind"] == FEE_KIND
    end

    def positive_int(value)
      parsed = integer_from(value)
      parsed&.positive? ? parsed : 0
    end

    def nonnegative_int(value)
      integer_from(value) || 0
    end

    def integer_from(value)
      return if value.blank?

      Integer(value, exception: false)
    end
  end
end
