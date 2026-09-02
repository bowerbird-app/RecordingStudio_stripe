# frozen_string_literal: true

module RecordingStudioStripe
  class UpsertPrice
    def self.call(stripe_price)
      new(stripe_price).call
    end

    def initialize(stripe_price)
      @stripe_price = stripe_price
    end

    def call
      product = Product.find_by(stripe_id: product_id)
      return unless product

      price = Price.find_or_initialize_by(stripe_id: @stripe_price.id)
      recurring = @stripe_price.try(:recurring)
      price.assign_attributes(
        product: product,
        unit_amount: @stripe_price.unit_amount.to_i,
        currency: @stripe_price.currency.to_s,
        interval: recurring.respond_to?(:interval) ? recurring.interval : recurring&.[]("interval"),
        active: @stripe_price.try(:active) != false,
        metadata: stringify(@stripe_price.try(:metadata))
      )
      price.save!
      price
    end

    private

    def product_id
      product = @stripe_price.product
      product.respond_to?(:id) ? product.id : product.to_s
    end

    def stringify(metadata)
      return {} if metadata.blank?

      metadata.to_h.stringify_keys
    end
  end
end
