# frozen_string_literal: true

module RecordingStudioStripe
  class UpdateProduct
    def self.call(product:, name:, description: nil, paywall_names: [], subscription_type: nil, limits: nil)
      new(
        product: product,
        name: name,
        description: description,
        paywall_names: paywall_names,
        subscription_type: subscription_type,
        limits: limits
      ).call
    end

    def initialize(product:, name:, description:, paywall_names:, subscription_type:, limits:)
      @product = product
      @name = name
      @description = description
      @paywall_names = paywall_names
      @subscription_type = subscription_type
      @limits = limits
    end

    def call
      type = SubscriptionTypes.normalize(@subscription_type.presence || @product.subscription_type)
      @product.assign_attributes(name: @name, description: @description, subscription_type: type)
      @product.metadata = @product.metadata.merge("subscription_type" => type)
      @product.assign_limits(@limits)
      update_stripe(type)
      @product.save!
      @product.assign_paywalls(@paywall_names)
      @product
    end

    private

    def update_stripe(type)
      return if RecordingStudioStripe.configuration.local_mode?

      stripe_product = Client.current.v1.products.retrieve(@product.stripe_id)
      existing = stringify(stripe_get(stripe_product, :metadata))
      Client.current.v1.products.update(
        @product.stripe_id,
        {
          name: @name,
          description: @description,
          metadata: existing.merge("kind" => @product.kind, "subscription_type" => type).merge(@product.limit_metadata)
        }
      )
    end

    def stringify(metadata)
      return {} if metadata.blank?

      metadata.to_h.stringify_keys
    end

    def stripe_get(object, key)
      return if object.nil?
      return object[key] || object[key.to_s] || object[key.to_sym] if object.is_a?(Hash)

      object.public_send(key)
    rescue NoMethodError
      object[key] || object[key.to_s] if object.respond_to?(:[])
    end
  end
end
