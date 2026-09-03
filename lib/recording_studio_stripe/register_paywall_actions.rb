# frozen_string_literal: true

module RecordingStudioStripe
  class RegisterPaywallActions
    def self.call
      new.call
    end

    def call
      return unless defined?(RecordingStudioAccessible)
      return unless Paywall.table_exists?

      Paywall.find_each do |paywall|
        register(paywall)
      end
    rescue ActiveRecord::ActiveRecordError
      nil
    end

    private

    def register(paywall)
      action = paywall.action_name
      name = paywall.name
      RecordingStudioAccessible.register_action(
        action,
        label: paywall.label,
        source: "recording_studio_stripe",
        recording_required: true
      )
      RecordingStudioAccessible.define_action(action) do |actor:, recording:, **|
        PaywallPolicy.allowed?(actor: actor, recording: recording, paywall_name: name)
      end
    end
  end
end
