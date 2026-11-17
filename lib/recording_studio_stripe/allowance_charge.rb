# frozen_string_literal: true

module RecordingStudioStripe
  # Maps a Stripe charge or dispute back to an allowance purchase.
  # Charges with no matching purchase are ignored. Callers still store the event.
  class AllowanceCharge
    def self.refund!(payment_intent_id:, amount_refunded:, amount:)
      purchase = find(payment_intent_id)
      return if purchase.blank?

      AllowanceCreditRevocation.refund!(purchase, amount_refunded: amount_refunded, amount: amount)
    end

    def self.freeze!(payment_intent_id:)
      purchase = find(payment_intent_id)
      return if purchase.blank?

      AllowanceCreditRevocation.freeze!(purchase)
    end

    def self.close_dispute!(payment_intent_id:, status:)
      purchase = find(payment_intent_id)
      return if purchase.blank?

      case status.to_s
      when "won", "warning_closed"
        AllowanceCreditRevocation.unfreeze!(purchase)
      when "lost"
        AllowanceCreditRevocation.revoke_unused!(purchase)
      end
    end

    def self.record_failure!(root:, price:, session_id:, payment_intent_id:)
      new(root, price, session_id, payment_intent_id).record_failure!
    end

    def self.find(payment_intent_id)
      return if payment_intent_id.blank?

      AllowancePurchase.find_by(stripe_payment_intent_id: payment_intent_id)
    end

    def initialize(root, price, session_id, payment_intent_id)
      @root = root
      @price = price
      @session_id = session_id.to_s.presence
      @payment_intent_id = payment_intent_id.presence
    end

    def record_failure!
      raise InvalidPrice, "Allowance Price needs meter and allowance metadata" unless grantable?

      existing = existing_purchase
      return fail_existing!(existing) if existing
      return if @session_id.blank?

      create_failed!
    end

    private

    def grantable?
      @price.allowance_meter_name.present? && @price.allowance_quantity.positive?
    end

    def existing_purchase
      return if @session_id.blank?

      AllowancePurchase.find_by(stripe_checkout_session_id: @session_id)
    end

    def fail_existing!(purchase)
      return purchase if purchase.failed?

      AllowanceCreditRevocation.revoke_unused!(purchase)
      purchase.update!(
        status: AllowancePurchase::STATUS_FAILED,
        credits_frozen: false,
        stripe_payment_intent_id: purchase.stripe_payment_intent_id.presence || @payment_intent_id
      )
      purchase
    end

    def create_failed!
      AllowancePurchase.create!(
        root_recording_id: @root.id,
        meter: Meter.fetch(@price.allowance_meter_name),
        customer: EnsureCustomer.call(root_recording: @root),
        price: @price,
        quantity: @price.allowance_quantity,
        stripe_checkout_session_id: @session_id,
        stripe_payment_intent_id: @payment_intent_id,
        purchased_at: Time.current,
        subscription_type: SubscriptionTypes.normalize(@price.product&.subscription_type),
        status: AllowancePurchase::STATUS_FAILED
      )
    end
  end
end
