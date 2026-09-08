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

    def to_name
      @to_price.product.name
    end

    def title
      return "Switch #{to_name} to #{interval_word(@to_price)}?" if same_product?
      return "Upgrade to #{to_name}?" if upgrade?

      "Switch to #{to_name}?"
    end

    def subtitle
      "#{amount(@to_price)}, #{change_word} from #{amount(@from_price)}. #{timing}"
    end

    def confirm_label
      upgrade? ? "Upgrade" : "Switch at renewal"
    end

    private

    def same_product?
      @from_price.product_id == @to_price.product_id
    end

    def amount(price)
      cadence = price.annual? ? "year" : "month"
      "#{price.formatted_amount}/#{cadence}"
    end

    def change_word
      upgrade? ? "up" : "down"
    end

    def timing
      return "You pay the difference today." if upgrade?
      return "Starts on #{renewal_label}." if renewal_date

      "Starts at the next renewal."
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
