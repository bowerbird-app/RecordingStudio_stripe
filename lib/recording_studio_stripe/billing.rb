# frozen_string_literal: true

module RecordingStudioStripe
  class Billing
    attr_reader :root_recording

    def self.for(recordable)
      recording = RecordingStudio.root_recording_for(recordable)
      new(root_recording: recording)
    end

    def self.for_recording(recording)
      root = recording.respond_to?(:root_recording) ? (recording.root_recording || recording) : recording
      new(root_recording: root)
    end

    def initialize(root_recording:)
      @root_recording = root_recording
    end

    def meter(name)
      MeterHandle.new(root_recording: root_recording, meter: Meter.named(name))
    end

    def customer
      Customer.find_by(root_recording_id: root_recording.id)
    end

    def subscription
      Subscription.current_for(root_recording_id: root_recording.id)
    end

    def subscribed?
      subscription&.active?
    end

    def unlocked?(paywall_name)
      return false unless subscribed?

      product = subscription.price&.product
      return false unless product&.plan?

      product.paywalls.exists?(name: paywall_name.to_s)
    end
  end
end
