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

    def record(quantity, idempotency_key: nil, recorded_at: Time.current, usage_key: nil,
               source_quantity: nil, credit_rate: nil)
      RecordingStudioStripe::RecordUsage.call(
        root_recording: root_recording,
        meter: meter,
        quantity: quantity,
        idempotency_key: idempotency_key,
        recorded_at: recorded_at,
        subscription_type: @subscription_type,
        usage_key: usage_key,
        source_quantity: source_quantity,
        credit_rate: credit_rate
      )
    end

    def spend(quantity, idempotency_key: nil, recorded_at: Time.current, usage_key: nil,
              source_quantity: nil, credit_rate: nil)
      UsageEntry.transaction do
        AdvisoryLock.hold(UsageEntry.connection, "#{root_recording.id}:meter:#{meter.name}")
        if idempotency_key.present?
          existing = UsageEntry.find_by(
            root_recording_id: root_recording.id,
            idempotency_key: idempotency_key
          )
          return existing if existing
        end
        raise MeterLimitReached.new(handle: self) unless available?(quantity)

        record(
          quantity,
          idempotency_key: idempotency_key,
          recorded_at: recorded_at,
          usage_key: usage_key,
          source_quantity: source_quantity,
          credit_rate: credit_rate
        )
      end
    end

    private

    def period
      UsagePeriod.for(
        root_recording: root_recording,
        meter: meter,
        subscription_type: @subscription_type
      )
    end
  end
end
