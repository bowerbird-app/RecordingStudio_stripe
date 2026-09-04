# frozen_string_literal: true

module RecordingStudioStripe
  class MeterHandle
    attr_reader :root_recording, :meter

    def initialize(root_recording:, meter:, subscription_type: nil)
      @root_recording = root_recording
      @meter = meter
      @subscription_type = subscription_type
    end

    def included
      period.included
    end

    def purchased
      period.purchased
    end

    def usage
      period.usage
    end

    def remaining
      [included + purchased - usage, 0].max
    end

    def available?(quantity)
      remaining >= quantity.to_i
    end

    def record(quantity, idempotency_key: nil, recorded_at: Time.current)
      RecordingStudioStripe::RecordUsage.call(
        root_recording: root_recording,
        meter: meter,
        quantity: quantity,
        idempotency_key: idempotency_key,
        recorded_at: recorded_at
      )
    end

    private

    def period
      @period ||= UsagePeriod.for(
        root_recording: root_recording,
        meter: meter,
        subscription_type: @subscription_type
      )
    end
  end
end
