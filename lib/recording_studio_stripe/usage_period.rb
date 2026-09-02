# frozen_string_literal: true

module RecordingStudioStripe
  class UsagePeriod
    attr_reader :root_recording, :meter, :starts_at, :ends_at

    def self.for(root_recording:, meter:)
      subscription = Subscription.current_for(root_recording_id: root_recording.id)
      starts_at, ends_at = if subscription&.current_period_start && subscription.current_period_end
                             [subscription.current_period_start, subscription.current_period_end]
                           else
                             now = Time.current
                             [now.beginning_of_month, now.end_of_month]
                           end
      new(root_recording: root_recording, meter: meter, starts_at: starts_at, ends_at: ends_at,
          subscription: subscription)
    end

    def initialize(root_recording:, meter:, starts_at:, ends_at:, subscription:)
      @root_recording = root_recording
      @meter = meter
      @starts_at = starts_at
      @ends_at = ends_at
      @subscription = subscription
    end

    def included
      return 0 unless @subscription

      @subscription.price&.included_quantity(meter.name).to_i
    end

    def purchased
      AllowancePurchase
        .where(root_recording_id: root_recording.id, meter_id: meter.id)
        .where(purchased_at: starts_at...ends_at)
        .sum(:quantity)
    end

    def usage
      UsageEntry
        .where(root_recording_id: root_recording.id, meter_id: meter.id)
        .where(recorded_at: starts_at...ends_at)
        .sum(:quantity)
    end
  end
end
