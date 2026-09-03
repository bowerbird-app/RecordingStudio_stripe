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

    def line(type)
      Line.new(root_recording: root_recording, subscription_type: SubscriptionTypes.normalize(type))
    end

    def lines
      SubscriptionTypes.keys.map { |key| line(key) }
    end

    def active_lines
      lines.select(&:subscribed?)
    end

    def meter(name)
      type = subscription&.subscription_type
      MeterHandle.new(root_recording: root_recording, meter: Meter.named(name), subscription_type: type)
    end

    def customer
      Customer.find_by(root_recording_id: root_recording.id)
    end

    def subscription
      Subscription.current_for(root_recording_id: root_recording.id)
    end

    def subscribed?
      active_lines.any?
    end

    def unlocked?(paywall_name)
      active_lines.any? { |entry| entry.unlocked?(paywall_name) }
    end

    class Line
      attr_reader :root_recording, :subscription_type

      def initialize(root_recording:, subscription_type:)
        @root_recording = root_recording
        @subscription_type = subscription_type.to_s
      end

      def label
        SubscriptionTypes.label(subscription_type)
      end

      def subscription
        Subscription.current_for(
          root_recording_id: root_recording.id,
          subscription_type: subscription_type
        )
      end

      def subscribed?
        subscription&.active? || false
      end

      def unlocked?(paywall_name)
        return false unless subscribed?

        product = subscription.price&.product
        return false unless product&.plan?

        product.paywalls.exists?(name: paywall_name.to_s)
      end

      def meter(name)
        MeterHandle.new(
          root_recording: root_recording,
          meter: Meter.named(name),
          subscription_type: subscription_type
        )
      end
    end
  end
end
