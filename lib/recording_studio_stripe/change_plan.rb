# frozen_string_literal: true

module RecordingStudioStripe
  class ChangePlan
    def self.call(root_recording:, price:, actor: nil)
      new(root_recording: root_recording, price: price, actor: actor).call
    end

    def initialize(root_recording:, price:, actor:)
      @root_recording = root_recording
      @price = price
      @actor = actor
    end

    def call
      raise InvalidPrice, "Choose a live Price" unless @price.active? && @price.recurring?

      subscription = Subscription.current_for(
        root_recording_id: @root_recording.id,
        subscription_type: SubscriptionTypes.normalize(@price.product&.subscription_type)
      )
      raise NoSubscription, "Start a subscription first" unless subscription

      comparison = ComparePrices.new(from: subscription.price, to: @price)
      if comparison.upgrade?
        apply_upgrade(subscription)
      elsif comparison.downgrade?
        schedule_downgrade(subscription)
      else
        subscription
      end
    end

    private

    def apply_upgrade(subscription)
      unless RecordingStudioStripe.configuration.local_mode?
        release_schedule(subscription)
        Client.current.v1.subscriptions.update(
          subscription.stripe_id,
          {
            items: [{ id: stripe_item_id(subscription), price: @price.stripe_id }],
            proration_behavior: "always_invoice",
            cancel_at_period_end: false
          },
          { idempotency_key: "upgrade-#{subscription.stripe_id}-#{@price.stripe_id}" }
        )
      end

      subscription.update!(
        price: @price,
        scheduled_price: nil,
        cancel_at_period_end: false,
        status: "active"
      )
      subscription
    end

    def schedule_downgrade(subscription)
      schedule_stripe_downgrade(subscription) unless RecordingStudioStripe.configuration.local_mode?

      subscription.update!(scheduled_price: @price, cancel_at_period_end: false)
      subscription
    end

    def schedule_stripe_downgrade(subscription)
      release_schedule(subscription)
      Client.current.v1.subscription_schedules.create(
        {
          from_subscription: subscription.stripe_id,
          end_behavior: "release",
          phases: [
            {
              items: [{ price: subscription.price.stripe_id, quantity: 1 }],
              start_date: subscription.current_period_start.to_i,
              end_date: subscription.current_period_end.to_i
            },
            {
              items: [{ price: @price.stripe_id, quantity: 1 }],
              start_date: subscription.current_period_end.to_i
            }
          ]
        },
        { idempotency_key: "downgrade-#{subscription.stripe_id}-#{@price.stripe_id}" }
      )
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
      items = stripe_get(stripe_subscription, :items)
      item = stripe_get(items, :data)&.first || (items.respond_to?(:first) ? items.first : nil)
      item_id = stripe_get(item, :id)
      raise NoSubscription, "Stripe has no item on this subscription" if item_id.blank?

      subscription.update!(metadata: subscription.metadata.merge("stripe_item_id" => item_id))
      item_id
    end

    def stripe_get(object, key)
      return if object.nil?
      return object[key] || object[key.to_s] || object[key.to_sym] if object.is_a?(Hash)

      object.public_send(key)
    rescue NoMethodError
      object[key] || object[key.to_s] if object.respond_to?(:[])
    end
  end
end
