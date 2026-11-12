# frozen_string_literal: true

module RecordingStudioStripe
  class CreditRates
    Row = Struct.new(
      :product_name, :kind, :interval, :currency, :unit_amount, :credits,
      :cents_per_credit, :cheapest, :note,
      keyword_init: true
    ) do
      def cents_label
        formatted = format("%.4f", cents_per_credit.to_f)
        formatted.sub(/0+\z/, "").sub(/\.\z/, "")
      end

      def cheapest_label
        cheapest ? "Cheapest" : "—"
      end
    end

    def self.rows
      new.rows
    end

    def rows
      Price.active.includes(:product).filter_map { |price| grant_for(price) }
           .group_by { |grant| grant.fetch(:currency) }
           .sort
           .flat_map { |_currency, grants| mark_cheapest(grants) }
    end

    private

    def grant_for(price)
      return unless listed?(price)

      credits = credits_for(price)
      return unless credits

      {
        price: price,
        credits: credits,
        currency: price.currency.to_s.downcase,
        rate: Rational(price.unit_amount.to_i, credits)
      }
    end

    def listed?(price)
      product = price.product
      return false unless product&.active?
      return false unless price.unit_amount.to_i.positive?
      return false if Trial.fee_kind?(price)
      return false if price.metadata.to_h.stringify_keys["kind"].to_s.casecmp?("trial")

      true
    end

    def credits_for(price)
      product = price.product
      if product.allowance? && price.interval.blank? && price.metadata.to_h["meter"].to_s == "credits"
        return positive_integer(price.metadata.to_h["allowance"])
      end
      return unless product.plan? && price.recurring?

      positive_integer(price.metadata.to_h["included_credits"])
    end

    def positive_integer(value)
      text = value.to_s
      return unless text.match?(/\A[1-9]\d*\z/)

      Integer(text)
    end

    def mark_cheapest(grants)
      best = grants.map { |grant| grant.fetch(:rate) }.min
      grants.map { |grant| row_for(grant, cheapest: grant.fetch(:rate) == best) }
            .sort_by { |row| [row.cents_per_credit, row.product_name.to_s, row.interval.to_s] }
    end

    def row_for(grant, cheapest:)
      price = grant.fetch(:price)
      plan = price.product.plan?
      Row.new(
        product_name: price.product.name,
        kind: plan ? "Plan" : "Pack",
        interval: price.interval.presence || "one-time",
        currency: grant.fetch(:currency).upcase,
        unit_amount: price.unit_amount.to_i,
        credits: grant.fetch(:credits),
        cents_per_credit: grant.fetch(:rate),
        cheapest: cheapest,
        note: plan ? "Assumes the whole price is for credits." : "—"
      )
    end
  end
end
