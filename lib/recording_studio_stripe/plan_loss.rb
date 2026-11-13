# frozen_string_literal: true

module RecordingStudioStripe
  # Entitlements on the old plan Product that the new one does not keep.
  # A nil new Product is an empty plan (the subscription ended).
  class PlanLoss
    def initialize(from_product:, to_product:, subscription_type:)
      @from_product = from_product
      @to_product = to_product
      @subscription_type = subscription_type
    end

    def loss?
      paywalls_lost.any? || limits_lowered.any?
    end

    def paywalls_lost
      @paywalls_lost ||= (paywall_names(@from_product) - paywall_names(@to_product)).sort
    end

    def limits_lowered
      @limits_lowered ||= lowered_rows.sort_by { |row| row[:name] }
    end

    private

    def lowered_rows
      Limits.for_subscription_type(@subscription_type).filter_map do |definition|
        lowered_limit(definition.name)
      end
    end

    def paywall_names(product)
      return [] unless product

      product.paywalls.map(&:name)
    end

    def lowered_limit(name)
      from = limit_number(@from_product, name)
      return if from.nil?

      to = limit_number(@to_product, name)
      return if to && to >= from

      { name: name, from: from, to: to }
    end

    def limit_number(product, name)
      return if product.nil?

      data = product.metadata.to_h.stringify_keys
      key = "limit_#{name}"
      return unless data.key?(key)

      number = Integer(data[key], exception: false)
      return if number.nil? || number <= 0

      number
    end
  end
end
