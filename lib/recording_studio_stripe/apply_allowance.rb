# frozen_string_literal: true

module RecordingStudioStripe
  class ApplyAllowance
    def self.call(root_recording:, price:, email: nil, stripe_checkout_session_id: nil, purchased_at: Time.current)
      new(
        root_recording: root_recording,
        price: price,
        email: email,
        stripe_checkout_session_id: stripe_checkout_session_id,
        purchased_at: purchased_at
      ).call
    end

    def initialize(root_recording:, price:, email:, stripe_checkout_session_id:, purchased_at:)
      @root_recording = root_recording
      @price = price
      @email = email
      @stripe_checkout_session_id = stripe_checkout_session_id
      @purchased_at = purchased_at
    end

    def call
      meter_name = @price.allowance_meter_name
      quantity = @price.allowance_quantity
      raise InvalidPrice, "Allowance Price needs meter and allowance metadata" if meter_name.blank? || quantity <= 0

      if @stripe_checkout_session_id.present?
        existing = AllowancePurchase.find_by(stripe_checkout_session_id: @stripe_checkout_session_id)
        return existing if existing
      end

      customer = EnsureCustomer.call(root_recording: @root_recording, email: @email)
      AllowancePurchase.create!(
        root_recording_id: @root_recording.id,
        meter: Meter.named(meter_name),
        customer: customer,
        price: @price,
        quantity: quantity,
        stripe_checkout_session_id: @stripe_checkout_session_id,
        purchased_at: @purchased_at
      )
    end
  end
end
