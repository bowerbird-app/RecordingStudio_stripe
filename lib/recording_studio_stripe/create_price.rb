# frozen_string_literal: true

module RecordingStudioStripe
  class CreatePrice
    def self.call(product:, unit_amount:, currency: "usd", interval: nil, metadata: {})
      new(product: product, unit_amount: unit_amount, currency: currency, interval: interval, metadata: metadata).call
    end

    def initialize(product:, unit_amount:, currency:, interval:, metadata:)
      @product = product
      @unit_amount = unit_amount.to_i
      @currency = currency.to_s
      @interval = interval.presence
      @metadata = metadata.stringify_keys
    end

    def call
      stripe_id = create_stripe_id
      Price.create!(
        stripe_id: stripe_id,
        product: @product,
        unit_amount: @unit_amount,
        currency: @currency,
        interval: @interval,
        metadata: @metadata
      )
    end

    private

    def create_stripe_id
      return "price_local_#{SecureRandom.hex(6)}" if RecordingStudioStripe.configuration.local_mode?

      params = {
        product: @product.stripe_id,
        unit_amount: @unit_amount,
        currency: @currency,
        metadata: @metadata
      }
      params[:recurring] = { interval: @interval } if @interval.present?
      Client.current.v1.prices.create(params).id
    end
  end
end
