# frozen_string_literal: true

module RecordingStudioStripe
  class CurrentPlanState
    TRIAL_ENDING_WITHIN_DAYS = 7

    def initialize(subscription)
      @subscription = subscription
    end

    def plan_name
      @subscription.price&.product&.name || Copy.t("plans.current_plan")
    end

    def price_text
      price = @subscription.price
      return if price.blank?

      Copy.t(
        "intervals.amount",
        amount: price.formatted_amount,
        interval: interval_label(price.interval)
      )
    end

    def description
      return if @subscription.price.present?

      Copy.t("billing.catching_up")
    end

    def status
      return :canceled if canceled?
      return :past_due if @subscription.past_due?
      return :trialing if @subscription.trialing?
      return :incomplete if @subscription.incomplete?

      :active
    end

    def renews_on
      return if @subscription.trialing? || @subscription.canceling? || @subscription.past_due? || canceled?

      days = days_until(@subscription.current_period_end)
      return if days.nil?
      return Copy.t("billing.renews_today") if days.zero?

      Copy.t("billing.renews_in", count: days)
    end

    def trial_ends_on
      return unless @subscription.trialing?

      days = days_until(@subscription.current_period_end)
      return if days.nil?
      return Copy.t("billing.trial_ends_today") if days.zero?

      Copy.t("billing.trial_ends_in", count: days)
    end

    def canceled?
      @subscription.status == "canceled"
    end

    def past_due?
      @subscription.past_due?
    end

    def canceling?
      @subscription.canceling?
    end

    def trial_ending?
      return false unless @subscription.trialing?

      days = days_until(@subscription.current_period_end)
      !days.nil? && days <= TRIAL_ENDING_WITHIN_DAYS
    end

    def group_label?
      SubscriptionTypes.keys.size > 1
    end

    def group_label
      @subscription.subscription_type_label
    end

    def show_period_end?
      canceling? && !canceled?
    end

    def scheduled_change?
      @subscription.scheduled_downgrade? && !canceling? && !canceled?
    end

    def period_end_description
      date = Copy.long_date(@subscription.current_period_end)
      return Copy.t("cancel.subtitle_period") if date.blank?

      Copy.t("billing.canceling", date: date)
    end

    def scheduled_name
      @subscription.scheduled_price.product.name
    end

    def subscription_type
      @subscription.subscription_type
    end

    def root_recording_id
      @subscription.root_recording_id
    end

    private

    def interval_label(interval)
      key = { "year" => "year", "week" => "week" }.fetch(interval.to_s, "month")
      Copy.t("intervals.names.#{key}")
    end

    def days_until(time)
      return unless time

      remaining = (time.in_time_zone.to_date - Time.zone.today).to_i
      remaining.negative? ? 0 : remaining
    end
  end
end
