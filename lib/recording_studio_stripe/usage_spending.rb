# frozen_string_literal: true

module RecordingStudioStripe
  module UsageSpending
    def spend_usage(key:, quantity: 1, idempotency_key: nil, recorded_at: Time.current)
      charge = UsageTariff.charge(key: key, quantity: quantity)
      credits_meter.spend(
        charge.credits,
        idempotency_key: idempotency_key,
        recorded_at: recorded_at,
        usage_key: charge.key,
        source_quantity: charge.quantity,
        credit_rate: charge.rate
      )
    end

    def usage_cost(key:, quantity: 1)
      UsageTariff.charge(key: key, quantity: quantity).credits
    end

    def usage_available?(key:, quantity: 1)
      charge = UsageTariff.charge(key: key, quantity: quantity)
      credits_meter.available?(charge.credits)
    end
  end
end
