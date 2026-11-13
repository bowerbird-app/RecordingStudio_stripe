# frozen_string_literal: true

module RecordingStudioStripe
  class CancelSubscription
    def self.call(root_recording:, subscription_type: nil)
      new(root_recording: root_recording, subscription_type: subscription_type).call
    end

    def initialize(root_recording:, subscription_type:)
      @root_recording = root_recording
      @subscription_type = subscription_type
    end

    def call
      subscription = live_subscription
      raise NoSubscription, Copy.t("alerts.nothing_to_cancel") unless subscription

      if downgrade_now?(subscription)
        cancel_now(subscription)
      else
        cancel_later(subscription)
      end
      subscription
    end

    private

    def downgrade_now?(subscription)
      SubscriptionTypes.downgrade_timing(subscription.subscription_type) == :immediately
    end

    def cancel_later(subscription)
      unless RecordingStudioStripe.configuration.local_mode?
        Client.current.v1.subscriptions.update(
          subscription.stripe_id,
          { cancel_at_period_end: true }
        )
      end

      subscription.update!(cancel_at_period_end: true)
    end

    def cancel_now(subscription)
      unless RecordingStudioStripe.configuration.local_mode?
        Client.current.v1.subscriptions.cancel(
          subscription.stripe_id,
          {},
          { idempotency_key: "cancel-#{subscription.stripe_id}-#{subscription.updated_at.to_i}" }
        )
        return
      end

      subscription.update!(status: "canceled", cancel_at_period_end: false)
    end

    def live_subscription
      LiveSubscription.find(
        root_recording: @root_recording,
        subscription_type: @subscription_type,
        missing_type_message: Copy.t("alerts.pick_which_cancel")
      )
    end
  end
end
