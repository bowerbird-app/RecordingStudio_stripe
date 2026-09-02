# frozen_string_literal: true

module RecordingStudioStripe
  class UpsertProduct
    def self.call(stripe_product)
      new(stripe_product).call
    end

    def initialize(stripe_product)
      @stripe_product = stripe_product
    end

    def call
      product = Product.find_or_initialize_by(stripe_id: @stripe_product.id)
      metadata = stringify(@stripe_product.try(:metadata))
      product.assign_attributes(
        name: @stripe_product.name,
        description: @stripe_product.try(:description),
        kind: metadata["kind"].presence_in(Product::KINDS) || product.kind || "plan",
        active: @stripe_product.try(:active) != false,
        metadata: metadata
      )
      product.save!
      product
    end

    private

    def stringify(metadata)
      return {} if metadata.blank?

      metadata.to_h.stringify_keys
    end
  end
end
