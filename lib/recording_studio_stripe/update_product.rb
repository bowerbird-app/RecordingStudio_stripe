# frozen_string_literal: true

module RecordingStudioStripe
  class UpdateProduct
    def self.call(product:, name:, description: nil, paywall_names: [])
      new(product: product, name: name, description: description, paywall_names: paywall_names).call
    end

    def initialize(product:, name:, description:, paywall_names:)
      @product = product
      @name = name
      @description = description
      @paywall_names = paywall_names
    end

    def call
      update_stripe
      @product.assign_attributes(name: @name, description: @description)
      @product.save!
      @product.assign_paywalls(@paywall_names)
      @product
    end

    private

    def update_stripe
      return if RecordingStudioStripe.configuration.local_mode?

      Client.current.v1.products.update(
        @product.stripe_id,
        {
          name: @name,
          description: @description
        }
      )
    end
  end
end
