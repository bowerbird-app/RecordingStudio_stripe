# frozen_string_literal: true

module RecordingStudioStripe
  class RecordCredits
    USAGE_KEY = "ai"

    def self.call(handle:, amount:, breakdown:, idempotency_key:)
      new(handle:, amount:, breakdown:, idempotency_key:).call
    end

    def self.positive_integer(value, label)
      return value if value.is_a?(Integer) && value.positive?

      raise ArgumentError, "#{label} must be a positive integer"
    end

    def initialize(handle:, amount:, breakdown:, idempotency_key:)
      @handle = handle
      @amount = amount
      @breakdown = breakdown
      @idempotency_key = idempotency_key
    end

    def call
      amount = self.class.positive_integer(@amount, "amount")
      key = required_key(@idempotency_key)
      payload = CreditBreakdown.parse(@breakdown)
      raise ArgumentError, "usage source belongs on the credits meter" unless @handle.meter.name == "credits"

      UsageEntry.transaction do
        AdvisoryLock.hold(UsageEntry.connection, lock_name)
        entry = @handle.record(
          amount,
          idempotency_key: key,
          usage_key: USAGE_KEY,
          breakdown: payload
        )
        warn_amount_mismatch(entry, amount)
        entry
      end
    end

    private

    def lock_name
      "#{@handle.root_recording.id}:meter:#{@handle.meter.name}"
    end

    def required_key(value)
      return value if value.is_a?(String) && !value.strip.empty?

      raise ArgumentError, "idempotency_key is required"
    end

    def warn_amount_mismatch(entry, amount)
      return if entry.quantity.to_i == amount

      Rails.logger.warn(
        "RecordingStudioStripe record_credits kept usage #{entry.id} for #{entry.idempotency_key}: " \
        "recorded #{entry.quantity.to_i}, ignored #{amount}"
      )
    end
  end
end
