# frozen_string_literal: true

module RecordingStudioStripe
  # A positive invoice whose Price is not in the catalogue yet. The webhook
  # stays stored, and replay emits invoice_paid after the Price syncs.
  class PricesPending
    def self.waiting?(webhook, snapshot)
      return false if snapshot.blank? || !InvoiceSnapshot.missing_prices?(snapshot)

      mark!(webhook)
      true
    end

    def self.mark!(webhook)
      return if webhook.blank? || pending?(webhook)

      invoice = webhook.payload.to_h["invoice"].to_h.merge("prices_pending" => true)
      webhook.update!(payload: webhook.payload.merge("invoice" => invoice))
    end

    def self.refresh!(webhook)
      snapshot = webhook&.payload.to_h["invoice"]
      return if snapshot.blank? || snapshot["prices_pending"] != true

      webhook.update!(payload: webhook.payload.merge("invoice" => InvoiceSnapshot.refresh(snapshot)))
    end

    def self.each_ready(older_than:, &)
      cutoff = Time.current - older_than
      WebhookEvent.where(event_type: "invoice.paid").where(created_at: ...cutoff)
                  .where("payload #>> '{invoice,prices_pending}' = 'true'")
                  .order(:created_at, :id).each(&)
    end

    def self.pending?(webhook)
      webhook&.payload.to_h.dig("invoice", "prices_pending") == true
    end
  end
end
