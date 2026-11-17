# frozen_string_literal: true

module RecordingStudioStripe
  # Takes allowance credits back without driving the live meter below zero.
  # Refund targets are cumulative: amount_refunded / amount of the original pack,
  # rounded down to whole credits. A repeat with the same total is a no-op.
  class AllowanceCreditRevocation
    def self.refund!(purchase, amount_refunded:, amount:)
      new(purchase).refund!(amount_refunded: amount_refunded, amount: amount)
    end

    def self.freeze!(purchase)
      new(purchase).freeze_credits!
    end

    def self.unfreeze!(purchase)
      new(purchase).unfreeze_credits!
    end

    def self.revoke_unused!(purchase)
      new(purchase).revoke_unused!
    end

    def initialize(purchase)
      @purchase = purchase
    end

    def refund!(amount_refunded:, amount:)
      refunded = amount_refunded.to_i
      locked do
        next if @purchase.failed? || refunded <= @purchase.refunded_amount.to_i

        apply_target!(credit_share(refunded, amount.to_i), refunded_amount: refunded)
      end
      @purchase
    end

    def freeze_credits!
      locked do
        next if @purchase.failed? || @purchase.credits_frozen?

        @purchase.update!(credits_frozen: true)
      end
      @purchase
    end

    def unfreeze_credits!
      locked do
        next unless @purchase.credits_frozen?

        @purchase.update!(credits_frozen: false)
      end
      @purchase
    end

    def revoke_unused!
      locked do
        next if @purchase.failed?

        apply_target!(@purchase.quantity.to_i)
        @purchase.update!(credits_frozen: false) if @purchase.credits_frozen?
      end
      @purchase
    end

    private

    def credit_share(refunded, amount)
      quantity = @purchase.quantity.to_i
      return 0 if refunded <= 0 || quantity <= 0
      return quantity if amount <= 0 || refunded >= amount

      (quantity * refunded) / amount
    end

    def apply_target!(target, extra = {})
      additional = target.to_i - settled_credits
      attrs = extra
      if additional.positive?
        actual = [additional, unused_credits].min
        attrs = attrs.merge(
          credits_revoked: @purchase.credits_revoked.to_i + actual,
          credit_shortfall: @purchase.credit_shortfall.to_i + (additional - actual)
        )
      end
      @purchase.update!(attrs) if attrs.present?
    end

    def settled_credits
      @purchase.credits_revoked.to_i + @purchase.credit_shortfall.to_i
    end

    def unused_credits
      period.unused_credits_for(@purchase)
    end

    def period
      root = RecordingStudio::Recording.find(@purchase.root_recording_id)
      UsagePeriod.for(
        root_recording: root,
        meter: @purchase.meter,
        subscription_type: @purchase.subscription_type
      )
    end

    def locked(&block)
      meter_name = @purchase.meter.name
      AllowancePurchase.transaction do
        AdvisoryLock.hold(
          AllowancePurchase.connection,
          "#{@purchase.root_recording_id}:meter:#{meter_name}"
        )
        @purchase.with_lock(&block)
      end
    end
  end
end
