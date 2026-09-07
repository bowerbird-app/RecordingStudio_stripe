# frozen_string_literal: true

module RecordingStudioStripe
  class PendingCheckout
    include StripeRequest

    def initialize(root_recording:, price:)
      @root_recording = root_recording
      @price = price
    end

    def expire_open!(type)
      Subscription.where(
        root_recording_id: @root_recording.id,
        subscription_type: type,
        status: "incomplete"
      ).find_each do |pending|
        session_id = pending.metadata.to_h["checkout_session_id"].presence
        remote = retrieve_checkout_session(session_id)
        return session_id if remote && stripe_get(remote, :status).to_s == "complete"

        expire_checkout_session(session_id) if session_id
        pending.update!(status: "incomplete_expired")
      end
      nil
    end

    def persist!(customer, session, type)
      Subscription.create!(
        stripe_id: "cs_pending_#{session.id}",
        root_recording_id: @root_recording.id,
        customer: customer,
        price: @price,
        subscription_type: type,
        status: "incomplete",
        current_period_start: Time.current,
        current_period_end: 24.hours.from_now,
        metadata: { "checkout_session_id" => session.id }
      )
    end

    private

    def retrieve_checkout_session(session_id)
      return if session_id.blank?

      Client.current.v1.checkout.sessions.retrieve(session_id)
    rescue Stripe::StripeError
      nil
    end

    def expire_checkout_session(session_id)
      Client.current.v1.checkout.sessions.expire(session_id)
    rescue Stripe::StripeError
      nil
    end
  end
end
