# frozen_string_literal: true

module RecordingStudioStripe
  class ApplyAllowance
    def self.call(root_recording:, price:, email: nil, stripe_checkout_session_id: nil,
                  stripe_payment_intent_id: nil, purchased_at: Time.current)
      new(
        root_recording: root_recording,
        price: price,
        email: email,
        stripe_checkout_session_id: stripe_checkout_session_id,
        stripe_payment_intent_id: stripe_payment_intent_id,
        purchased_at: purchased_at
      ).call
    end

    def initialize(root_recording:, price:, email:, stripe_checkout_session_id:, stripe_payment_intent_id:,
                   purchased_at:)
      @root_recording = root_recording
      @price = price
      @email = email
      @stripe_checkout_session_id = stripe_checkout_session_id
      @stripe_payment_intent_id = stripe_payment_intent_id.presence
      @purchased_at = purchased_at
    end

    def call
      meter_name = @price.allowance_meter_name
      quantity = @price.allowance_quantity
      raise InvalidPrice, "Allowance Price needs meter and allowance metadata" if meter_name.blank? || quantity <= 0

      existing = existing_purchase
      return remember_payment_intent(existing) if existing

      customer = EnsureCustomer.call(root_recording: @root_recording, email: @email)
      AllowancePurchase.create!(
        root_recording_id: @root_recording.id,
        meter: Meter.fetch(meter_name),
        customer: customer,
        price: @price,
        quantity: quantity,
        stripe_checkout_session_id: @stripe_checkout_session_id,
        stripe_payment_intent_id: @stripe_payment_intent_id,
        purchased_at: @purchased_at,
        subscription_type: SubscriptionTypes.normalize(@price.product&.subscription_type),
        status: AllowancePurchase::STATUS_ACTIVE
      )
    end

    private

    def existing_purchase
      return if @stripe_checkout_session_id.blank?

      AllowancePurchase.find_by(stripe_checkout_session_id: @stripe_checkout_session_id)
    end

    def remember_payment_intent(purchase)
      if purchase.stripe_payment_intent_id.blank? && @stripe_payment_intent_id.present?
        purchase.update!(stripe_payment_intent_id: @stripe_payment_intent_id)
      end
      purchase
    end
  end
end
