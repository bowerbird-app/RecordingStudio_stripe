# frozen_string_literal: true

module RecordingStudioStripe
  class ScheduleDowngrade
    include StripeRequest

    def initialize(subscription:, price:)
      @subscription = subscription
      @price = price
    end

    def call
      release_schedule
      key = plan_change_key
      stripe_sub = Client.current.v1.subscriptions.retrieve(@subscription.stripe_id)
      schedule = Client.current.v1.subscription_schedules.create(
        { from_subscription: @subscription.stripe_id },
        { idempotency_key: "#{key}-create" }
      )
      Client.current.v1.subscription_schedules.update(
        stripe_get(schedule, :id),
        { end_behavior: "release", phases: phases(schedule, stripe_sub) },
        { idempotency_key: "#{key}-phases" }
      )
    end

    private

    def phases(schedule, stripe_sub)
      current = stripe_list_first(stripe_get(schedule, :phases))
      period_start = unix_time(stripe_get(current, :start_date)) || unix_time(@subscription.current_period_start)
      period_end = unix_time(stripe_get(current, :end_date)) || unix_time(@subscription.current_period_end)
      discounts = stripe_get(current, :discounts)
      [
        phase_hash(phase_items(stripe_sub, nil), period_start, period_end, discounts),
        phase_hash(phase_items(stripe_sub, @price.stripe_id), period_end, nil, discounts)
      ]
    end

    def phase_hash(items, start_date, end_date, discounts)
      phase = { items: items, start_date: start_date }
      phase[:end_date] = end_date if end_date
      phase[:discounts] = discounts if discounts.present?
      phase
    end

    def phase_items(stripe_sub, replacement_price_id)
      current_price = @subscription.price&.stripe_id.to_s
      mapped = stripe_list_items(stripe_get(stripe_sub, :items)).filter_map do |item|
        mapped_phase_item(item, current_price, replacement_price_id)
      end
      return mapped if mapped.any?

      [{ price: replacement_price_id.presence || current_price, quantity: 1 }]
    end

    def mapped_phase_item(item, current_price, replacement_price_id)
      price_id = item_price_id(item)
      return if price_id.blank?

      next_price = replacement_price_id.presence && price_id == current_price ? replacement_price_id : price_id
      { price: next_price, quantity: stripe_get(item, :quantity).presence || 1 }
    end

    def plan_change_key
      from = @subscription.price.stripe_id
      "downgrade-#{@subscription.stripe_id}-#{from}-#{@price.stripe_id}-#{@subscription.updated_at.to_i}"
    end

    def unix_time(value)
      return if value.blank?
      return value.to_i if value.respond_to?(:to_i)

      value
    end

    def release_schedule
      stripe_subscription = Client.current.v1.subscriptions.retrieve(@subscription.stripe_id)
      schedule_id = stripe_get(stripe_subscription, :schedule)
      return if schedule_id.blank?

      Client.current.v1.subscription_schedules.release(schedule_id)
    end
  end
end
