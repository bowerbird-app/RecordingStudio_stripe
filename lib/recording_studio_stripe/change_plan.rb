# frozen_string_literal: true

module RecordingStudioStripe
  class ChangePlan
    include StripeRequest

    def self.call(root_recording:, price:, actor: nil)
      new(root_recording: root_recording, price: price, actor: actor).call
    end

    def initialize(root_recording:, price:, actor:)
      @root_recording = root_recording
      @price = price
      @actor = actor
    end

    def call
      raise InvalidPrice, "Choose a live Price" unless live_plan_price?

      subscription = current_subscription
      raise NoSubscription, "Start a subscription first" unless subscription

      apply_comparison(subscription)
    end

    private

    def live_plan_price?
      @price.active? && @price.recurring? && @price.product&.plan?
    end

    def current_subscription
      Subscription.current_for(
        root_recording_id: @root_recording.id,
        subscription_type: SubscriptionTypes.normalize(@price.product&.subscription_type)
      )
    end

    def apply_comparison(subscription)
      comparison = ComparePrices.new(from: subscription.price, to: @price)
      return apply_upgrade(subscription) if comparison.upgrade?
      return schedule_downgrade(subscription) if comparison.downgrade?

      subscription
    end

    def apply_upgrade(subscription)
      if RecordingStudioStripe.configuration.local_mode?
        subscription.update!(
          price: @price,
          scheduled_price: nil,
          cancel_at_period_end: false,
          status: "active"
        )
        return subscription
      end

      release_schedule(subscription)
      begin
        Client.current.v1.subscriptions.update(
          subscription.stripe_id,
          {
            items: [{ id: stripe_item_id(subscription), price: @price.stripe_id }],
            proration_behavior: "always_invoice",
            payment_behavior: "error_if_incomplete",
            cancel_at_period_end: false
          },
          { idempotency_key: "#{plan_change_key('upgrade', subscription)}-update" }
        )
      rescue Stripe::StripeError => e
        raise unless incomplete_upgrade?(e)

        return subscription
      end

      subscription
    end

    def incomplete_upgrade?(error)
      error.is_a?(Stripe::CardError) ||
        error.message.to_s.match?(/incomplete|authentication|declined|requires/i)
    end

    def schedule_downgrade(subscription)
      unless RecordingStudioStripe.configuration.local_mode?
        ScheduleDowngrade.new(subscription: subscription, price: @price).call
      end

      subscription.update!(scheduled_price: @price, cancel_at_period_end: false)
      subscription
    end

    def plan_change_key(action, subscription)
      from = subscription.price.stripe_id
      "#{action}-#{subscription.stripe_id}-#{from}-#{@price.stripe_id}-#{subscription.updated_at.to_i}"
    end

    def release_schedule(subscription)
      stripe_subscription = Client.current.v1.subscriptions.retrieve(subscription.stripe_id)
      schedule_id = stripe_get(stripe_subscription, :schedule)
      return if schedule_id.blank?

      Client.current.v1.subscription_schedules.release(schedule_id)
    end

    def stripe_item_id(subscription)
      stored = subscription.metadata.to_h["stripe_item_id"].presence
      return stored if stored.present? && stored != "si_current"

      fetch_stripe_item_id(subscription)
    end

    def fetch_stripe_item_id(subscription)
      stripe_subscription = Client.current.v1.subscriptions.retrieve(subscription.stripe_id)
      item = matching_item(stripe_subscription, subscription.price&.stripe_id)
      item_id = stripe_get(item, :id)
      raise NoSubscription, "Stripe has no item on this subscription" if item_id.blank?

      subscription.update!(metadata: subscription.metadata.merge("stripe_item_id" => item_id))
      item_id
    end

    def matching_item(stripe_subscription, preferred_price_id)
      items = stripe_list_items(stripe_get(stripe_subscription, :items))
      if preferred_price_id.present?
        match = items.find { |item| item_price_id(item) == preferred_price_id.to_s }
        return match if match
      end
      items.first
    end
  end
end
