# frozen_string_literal: true

module RecordingStudioStripe
  class ResumeSubscription
    def self.call(root_recording:)
      new(root_recording: root_recording).call
    end

    def initialize(root_recording:)
      @root_recording = root_recording
    end

    def call
      subscription = Subscription.current_for(root_recording_id: @root_recording.id)
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
  end
end
