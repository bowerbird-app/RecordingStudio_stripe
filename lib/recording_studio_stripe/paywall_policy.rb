# frozen_string_literal: true

module RecordingStudioStripe
  class PaywallPolicy
    def self.allowed?(actor:, recording:, paywall_name:)
      return false unless defined?(RecordingStudioAccessible)
      return false if actor.blank? || recording.blank? || paywall_name.blank?

      RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: :view) &&
        Billing.for_recording(recording).unlocked?(paywall_name)
    end
  end
end
