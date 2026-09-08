# frozen_string_literal: true

module RecordingStudioStripe
  class PlanChange
    attr_reader :subscription, :from_price, :to_price

    def self.build(root_recording:, price_id:)
      price = Price.active.includes(:product).find_by(id: price_id)
      return unless price&.product&.plan? && price.recurring?

      subscription = Subscription.current_for(
        root_recording_id: root_recording.id,
        subscription_type: SubscriptionTypes.normalize(price.product.subscription_type)
      )
      return unless subscription&.active?
      return if subscription.price_id == price.id

      new(subscription: subscription, price: price)
    end

    def initialize(subscription:, price:)
      @subscription = subscription
      @from_price = subscription.price
      @to_price = price
      @comparison = ComparePrices.new(from: @from_price, to: @to_price)
    end

    def upgrade?
      @comparison.upgrade?
    end

    def downgrade?
      @comparison.downgrade?
    end

    def from_name
      @from_price.product.name
    end

    def to_name
      @to_price.product.name
    end

    def title
      return "Switch #{to_name} to #{interval_word(@to_price)}?" if same_product?
      return "Upgrade to #{to_name}?" if upgrade?

      "Switch to #{to_name}?"
    end

    def subtitle
      return "You pay the difference today." if upgrade?
      return "#{to_name} starts on #{renewal_label}. You keep #{from_name} until then." if renewal_date

      "#{to_name} starts at the next renewal. You keep #{from_name} until then."
    end

    def confirm_label
      upgrade? ? "Upgrade" : "Switch at renewal"
    end

    def next_badge
      upgrade? ? "Next" : "From renewal"
    end

    private

    def same_product?
      @from_price.product_id == @to_price.product_id
    end

    def interval_word(price)
      price.annual? ? "yearly" : "monthly"
    end

    def renewal_date
      @subscription.current_period_end&.to_date
    end

    def renewal_label
      renewal_date.to_fs(:long)
    end
  end
end
