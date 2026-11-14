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
        lowered_limit(definition)
      end
    end

    def paywall_names(product)
      return [] unless product

      product.paywalls.map(&:name)
    end

    def lowered_limit(definition)
      from = ceiling_for(definition, @from_product)
      to = @to_product.nil? ? empty_ceiling(definition) : ceiling_for(definition, @to_product)
      return unless lower?(definition, from, to)

      { name: definition.name, from: from, to: to }
    end

    def empty_ceiling(definition)
      definition.no_plan_limit
    end

    def ceiling_for(definition, product)
      return if product.nil?

      raw = product.metadata.to_h.stringify_keys["limit_#{definition.name}"]
      definition.per_item? ? per_item_number(raw) : count_number(raw)
    end

    def per_item_number(raw)
      return if raw.nil? || raw.to_s.strip.empty?

      Integer(raw, exception: false)
    end

    def count_number(raw)
      number = Integer(raw.to_s, exception: false)
      return if number.nil? || number <= 0

      number
    end

    def lower?(definition, from, to)
      return per_item_lower?(from, to) if definition.per_item?

      from && (to.nil? || to < from)
    end

    def per_item_lower?(from, to)
      return false if to.nil?
      return true if from.nil?

      to < from
    end
  end
end
