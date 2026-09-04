# frozen_string_literal: true

module RecordingStudioStripe
  class CreateProduct
    def self.call(name:, kind:, description: nil, active: true, paywall_names: [], subscription_type: nil)
      new(
        name: name,
        kind: kind,
        description: description,
        active: active,
        paywall_names: paywall_names,
        subscription_type: subscription_type
      ).call
    end

    def initialize(name:, kind:, description:, active:, paywall_names:, subscription_type:)
      @name = name
      @kind = kind
      @description = description
      @active = active
      @paywall_names = paywall_names
      @subscription_type = subscription_type
    end

    def call
      raise InvalidPrice, "Kind must be plan or allowance" unless Product::KINDS.include?(@kind)

      type = SubscriptionTypes.normalize(@subscription_type)
      raise InvalidPrice, "Unknown plan group" if @kind == "plan" && !SubscriptionTypes.known?(type)

      stripe_id = create_stripe_id(type)
      product = Product.create!(
        stripe_id: stripe_id,
        name: @name,
        description: @description,
        kind: @kind,
        active: @active,
        subscription_type: type,
        metadata: { "kind" => @kind, "subscription_type" => type }
      )
      product.assign_paywalls(@paywall_names)
      product
    end

    private

    def create_stripe_id(type)
      return "prod_local_#{SecureRandom.hex(6)}" if RecordingStudioStripe.configuration.local_mode?

      result = Client.current.v1.products.create(
        {
          name: @name,
          description: @description,
          metadata: { kind: @kind, subscription_type: type }
        }
      )
      result.id
    end
  end
end
