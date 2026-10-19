# frozen_string_literal: true

module RecordingStudioStripe
  # first_payment for one local Subscription.
  # A positive subscription_create is first when no invoice_paid row exists yet.
  # A fee or zero create is not recorded. The next positive invoice is first
  # only when payments_tracked is set. A local row reused for a new Stripe
  # Subscription does not start over. Replay of a missing row computes this
  # again. A stored row keeps the value it was saved with.
  class InvoicePayment
    def self.first?(subscription, snapshot)
      return false if DomainEvent.exists?(subscription_id: subscription.id, name: "invoice_paid")
      return true if snapshot.to_h["billing_reason"].to_s == "subscription_create"

      subscription.metadata.to_h.stringify_keys["payments_tracked"] == true
    end
  end
end
