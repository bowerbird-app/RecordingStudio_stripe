# frozen_string_literal: true

module RecordingStudioStripe
  class RecordUsage
    def self.call(root_recording:, meter:, quantity:, idempotency_key: nil, recorded_at: Time.current,
                  subscription_type: nil, usage_key: nil, source_quantity: nil, credit_rate: nil)
      new(
        root_recording: root_recording,
        meter: meter,
        quantity: quantity,
        idempotency_key: idempotency_key,
        recorded_at: recorded_at,
        subscription_type: subscription_type,
        usage_key: usage_key,
        source_quantity: source_quantity,
        credit_rate: credit_rate
      ).call
    end

    def initialize(root_recording:, meter:, quantity:, idempotency_key:, recorded_at:, subscription_type:,
                   usage_key:, source_quantity:, credit_rate:)
      @root_recording = root_recording
      @meter = meter
      @quantity = quantity.to_i
      @idempotency_key = idempotency_key
      @recorded_at = recorded_at
      @subscription_type = subscription_type
      @usage_key = usage_key
      @source_quantity = source_quantity
      @credit_rate = credit_rate
    end

    def call
      raise ArgumentError, "quantity must be positive" if @quantity <= 0

      if @idempotency_key.present?
        existing = existing_usage
        return existing if existing
      end

      UsageEntry.create!(
        root_recording_id: @root_recording.id,
        meter: @meter,
        quantity: @quantity,
        recorded_at: @recorded_at,
        idempotency_key: @idempotency_key,
        subscription_type: @subscription_type,
        usage_key: @usage_key,
        source_quantity: @source_quantity,
        credit_rate: @credit_rate
      )
    rescue ActiveRecord::RecordNotUnique
      existing_usage || raise
    end

    private

    def existing_usage
      return if @idempotency_key.blank?

      UsageEntry.find_by(root_recording_id: @root_recording.id, idempotency_key: @idempotency_key)
    end
  end
end
