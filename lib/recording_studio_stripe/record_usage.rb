# frozen_string_literal: true

module RecordingStudioStripe
  class RecordUsage
    def self.call(root_recording:, meter:, quantity:, idempotency_key: nil, recorded_at: Time.current)
      new(
        root_recording: root_recording,
        meter: meter,
        quantity: quantity,
        idempotency_key: idempotency_key,
        recorded_at: recorded_at
      ).call
    end

    def initialize(root_recording:, meter:, quantity:, idempotency_key:, recorded_at:)
      @root_recording = root_recording
      @meter = meter
      @quantity = quantity.to_i
      @idempotency_key = idempotency_key
      @recorded_at = recorded_at
    end

    def call
      raise ArgumentError, "quantity must be positive" if @quantity <= 0

      if @idempotency_key.present?
        existing = UsageEntry.find_by(idempotency_key: @idempotency_key)
        return existing if existing
      end

      UsageEntry.create!(
        root_recording_id: @root_recording.id,
        meter: @meter,
        quantity: @quantity,
        recorded_at: @recorded_at,
        idempotency_key: @idempotency_key
      )
    end
  end
end
