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
      return Copy.t("change.title_switch", name: to_name, interval: interval_word(@to_price)) if same_product?
      return Copy.t("change.title_upgrade", name: to_name) if upgrade?

      Copy.t("change.title_downgrade", name: to_name)
    end

    def subtitle
      Copy.t(
        "change.subtitle",
        to_amount: amount(@to_price),
        direction: change_word,
        from_amount: amount(@from_price),
        timing: timing
      )
    end

    def confirm_label
      upgrade? ? Copy.t("plans.upgrade") : Copy.t("plans.downgrade")
    end

    private

    def same_product?
      @from_price.product_id == @to_price.product_id
    end

    def amount(price)
      Copy.t("intervals.amount", amount: price.formatted_amount, interval: interval_name(price.interval))
    end

    def change_word
      upgrade? ? Copy.t("change.up") : Copy.t("change.down")
    end

    def timing
      return Copy.t("change.pay_difference") if upgrade?
      return Copy.t("change.starts_on", date: Copy.long_date(renewal_date)) if renewal_date

      Copy.t("change.starts_next")
    end

    def interval_word(price)
      adjective_key = { "year" => "yearly", "week" => "weekly" }.fetch(price.interval, "monthly")
      Copy.t("intervals.adjectives.#{adjective_key}")
    end

    def interval_name(interval)
      name_key = { "year" => "year", "week" => "week" }.fetch(interval, "month")
      Copy.t("intervals.names.#{name_key}")
    end

    def renewal_date
      @subscription.current_period_end&.to_date
    end
  end
end
