# frozen_string_literal: true

module RecordingStudioStripe
  class UpdatePrice
    include StripeRequest

    def self.call(price:, metadata:)
      new(price: price, metadata: metadata).call
    end

    def initialize(price:, metadata:)
      @price = price
      @metadata = metadata.to_h.stringify_keys
    end

    def call
      @price.metadata = merge_metadata(@price.metadata, @metadata)
      update_stripe
      @price.save!
      @price
    end

    private

    def update_stripe
      return if RecordingStudioStripe.configuration.local_mode?

      stripe_price = Client.current.v1.prices.retrieve(@price.stripe_id)
      existing = stringify_metadata(stripe_get(stripe_price, :metadata))
      Client.current.v1.prices.update(
        @price.stripe_id,
        { metadata: merge_metadata(existing, @metadata) }
      )
    end

    def merge_metadata(current, incoming)
      data = stringify_metadata(current)
      incoming.each do |key, value|
        if value.blank?
          data.delete(key)
        else
          data[key] = value.to_s
        end
      end
      data
    end
  end
end
