# frozen_string_literal: true

module RecordingStudioStripe
  class UpdateProduct
    def self.call(product:, name:, description: nil, paywall_names: [], subscription_type: nil)
      new(
        product: product,
        name: name,
        description: description,
        paywall_names: paywall_names,
        subscription_type: subscription_type
      ).call
    end

    def initialize(product:, name:, description:, paywall_names:, subscription_type:)
      @product = product
      @name = name
      @description = description
      @paywall_names = paywall_names
      @subscription_type = subscription_type
    end

    def call
      type = SubscriptionTypes.normalize(@subscription_type.presence || @product.subscription_type)
      update_stripe(type)
      @product.assign_attributes(name: @name, description: @description, subscription_type: type)
      @product.metadata = @product.metadata.merge("subscription_type" => type)
      @product.save!
      @product.assign_paywalls(@paywall_names)
      @product
    end

    private

    def update_stripe(type)
      return if RecordingStudioStripe.configuration.local_mode?

      Client.current.v1.products.update(
        @product.stripe_id,
        {
          name: @name,
          description: @description,
          metadata: { kind: @product.kind, subscription_type: type }
        }
      )
    end
  end
end
