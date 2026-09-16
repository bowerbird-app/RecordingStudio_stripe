# frozen_string_literal: true

module RecordingStudioStripe
  class ClearScheduledChange
    include StripeRequest

    def self.call(root_recording:, subscription_type: nil)
      new(root_recording: root_recording, subscription_type: subscription_type).call
    end

    def initialize(root_recording:, subscription_type:)
      @root_recording = root_recording
      @subscription_type = subscription_type
    end

    def call
      subscription = live_subscription
      raise NoSubscription, "Nothing is scheduled" unless subscription&.scheduled_downgrade?

      release_schedule(subscription) unless RecordingStudioStripe.configuration.local_mode?
      subscription.update!(scheduled_price: nil)
      subscription
    end

    private

    def live_subscription
      LiveSubscription.find(
        root_recording: @root_recording,
        subscription_type: @subscription_type,
        missing_type_message: "Pick which plan to keep."
      )
    end

    def release_schedule(subscription)
      stripe_subscription = Client.current.v1.subscriptions.retrieve(subscription.stripe_id)
      schedule_id = stripe_get(stripe_subscription, :schedule)
      return if schedule_id.blank?

      Client.current.v1.subscription_schedules.release(schedule_id)
    end
  end
end
