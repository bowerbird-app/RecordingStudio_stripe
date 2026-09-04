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
      subscription = Subscription.current_for(
        root_recording_id: @root_recording.id,
        subscription_type: @subscription_type.presence
      )
      raise NoSubscription, "Nothing to cancel" unless subscription

      unless RecordingStudioStripe.configuration.local_mode?
        Client.current.v1.subscriptions.update(
          subscription.stripe_id,
          { cancel_at_period_end: true }
        )
      end

      subscription.update!(cancel_at_period_end: true)
      subscription
    end
  end
end
