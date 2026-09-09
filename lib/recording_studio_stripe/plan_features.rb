# frozen_string_literal: true

module RecordingStudioStripe
  class PlanFeatures
    Line = Data.define(:key, :text, :icon)

    FALLBACK_NO_PRICE = "This plan is a seat. Usage limits show up once a Price is attached."
    FALLBACK_EMPTY = "A seat. Standing caps show on billing."
    DEFAULT_ICON = "check"

    def self.for(product, price)
      new(product, price).lines
    end

    def self.quantity_label(quantity)
      number = quantity.to_i
      return number.to_s if number < 1_000
      return "#{number / 1_000}k" if number < 1_000_000

      "#{number / 1_000_000}m"
    end

    def self.hide_options(subscription_type:)
      PlanCardOptions.hide_list(subscription_type: subscription_type)
    end

    def initialize(product, price)
      @product = product
      @price = price
    end

    def lines
      return [fallback(FALLBACK_NO_PRICE)] unless @price

      visible = ordered(candidates.reject { |line| hidden?(line.key) })
      visible.presence || [fallback(FALLBACK_EMPTY)]
    end

    private

    def candidates
      PlanFeatureCandidates.new(@product, @price, settings).lines
    end

    def hidden?(key)
      Array(settings["hide"]).map(&:to_s).include?(key)
    end

    def ordered(lines)
      ranking = order_keys
      return lines if ranking.empty?

      ranked, rest = lines.partition { |line| ranking.include?(line.key) }
      ranked.sort_by { |line| ranking.index(line.key) } + rest
    end

    def order_keys
      Array(settings["order"]).map(&:to_s).map(&:strip).reject(&:blank?)
    end

    def settings
      return {} unless @product.respond_to?(:plan_card_settings)

      @product.plan_card_settings.to_h.stringify_keys
    end

    def fallback(text)
      Line.new(key: "fallback", text: text, icon: DEFAULT_ICON)
    end
  end
end
