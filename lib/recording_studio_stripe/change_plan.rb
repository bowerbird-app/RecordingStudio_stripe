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
        Client.current.v1.subscriptions.update(
          subscription.stripe_id,
          {
            items: [{ id: stripe_item_id(subscription), price: @price.stripe_id }],
            proration_behavior: "always_invoice",
            cancel_at_period_end: false
          }
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
        }
      )
    rescue Stripe::InvalidRequestError
      Client.current.v1.subscriptions.update(
        subscription.stripe_id,
        {
          items: [{ id: stripe_item_id(subscription), price: @price.stripe_id }],
          proration_behavior: "none",
          billing_cycle_anchor: "unchanged"
        }
      )
    end

    def stripe_item_id(subscription)
      subscription.metadata.to_h["stripe_item_id"].presence || "si_current"
    end
  end
end
