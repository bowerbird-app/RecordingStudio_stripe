# frozen_string_literal: true

module RecordingStudioStripe
  class UpdatePrice
    def self.call(price:, metadata:)
      new(price: price, metadata: metadata).call
    end

    def initialize(price:, metadata:)
      @price = price
      @metadata = metadata.to_h.stringify_keys
    end

    def call
      @price.metadata = (@price.metadata || {}).stringify_keys.merge(@metadata)
      update_stripe
      @price.save!
      @price
    end

    private

    def update_stripe
      return if RecordingStudioStripe.configuration.local_mode?

      stripe_price = Client.current.v1.prices.retrieve(@price.stripe_id)
      existing = stringify(stripe_get(stripe_price, :metadata))
      Client.current.v1.prices.update(
        @price.stripe_id,
        { metadata: existing.merge(@metadata) }
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
