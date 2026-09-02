# frozen_string_literal: true

module RecordingStudioStripe
  class CreateProduct
    def self.call(name:, kind:, description: nil, active: true)
      new(name: name, kind: kind, description: description, active: active).call
    end

    def initialize(name:, kind:, description:, active:)
      @name = name
      @kind = kind
      @description = description
      @active = active
    end

    def call
      raise InvalidPrice, "Kind must be plan or allowance" unless Product::KINDS.include?(@kind)

      stripe_id = create_stripe_id
      Product.create!(
        stripe_id: stripe_id,
        name: @name,
        description: @description,
        kind: @kind,
        active: @active,
        metadata: { "kind" => @kind }
      )
    end

    private

    def create_stripe_id
      return "prod_local_#{SecureRandom.hex(6)}" if RecordingStudioStripe.configuration.local_mode?

      result = Client.current.v1.products.create(
        {
          name: @name,
          description: @description,
          metadata: { kind: @kind }
        }
      )
      result.id
    end
  end
end
