# frozen_string_literal: true

module RecordingStudioStripe
  class ResumeSubscription
    def self.call(root_recording:, subscription_type: nil)
      new(root_recording: root_recording, subscription_type: subscription_type).call
    end

    def initialize(root_recording:, subscription_type:)
      @root_recording = root_recording
      @subscription_type = subscription_type
    end

    def call
      subscription = live_subscription
      raise NoSubscription, "Nothing to resume" unless subscription

      unless RecordingStudioStripe.configuration.local_mode?
        Client.current.v1.subscriptions.update(
          subscription.stripe_id,
          { cancel_at_period_end: false }
        )
      end

      subscription.update!(cancel_at_period_end: false)
      subscription
    end

    private

    def live_subscription
      LiveSubscription.find(
        root_recording: @root_recording,
        subscription_type: @subscription_type,
        missing_type_message: "Pick which plan to resume."
      )
    end
  end
end
