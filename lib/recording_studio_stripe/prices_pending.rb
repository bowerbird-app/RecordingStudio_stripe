# frozen_string_literal: true

module RecordingStudioStripe
  # A positive invoice whose Price is not in the catalogue yet. The webhook
  # stays stored, and the pending sweep emits invoice_paid after the Price syncs.
  class PricesPending
    BATCH_SIZE = 100
    PENDING_SQL = "payload #>> '{invoice,prices_pending}' = 'true'"

    def self.waiting?(webhook, snapshot)
      return false if snapshot.blank? || !InvoiceSnapshot.missing_prices?(snapshot)

      mark!(webhook)
      true
    end

    # A later invoice must not become first_payment while an older one for the
    # same Stripe Subscription is still waiting on a Price.
    def self.hold_for_older?(webhook, snapshot)
      return false unless older_pending?(webhook, snapshot)

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

      refreshed = InvoiceSnapshot.refresh(snapshot)
      refreshed["prices_pending"] = true if older_pending?(webhook, refreshed)
      webhook.update!(payload: webhook.payload.merge("invoice" => refreshed))
    end

    # Prices are in the catalogue, but the local Subscription is gone.
    # Caller reports this before refresh clears prices_pending.
    def self.missing_subscription(webhook)
      snapshot = webhook&.payload.to_h["invoice"]
      return if snapshot.blank? || snapshot["prices_pending"] != true
      return if InvoiceSnapshot.missing_prices?(snapshot)

      stripe_subscription_id = snapshot["subscription"].to_s
      return if stripe_subscription_id.blank?
      return if Subscription.exists?(stripe_id: stripe_subscription_id)

      DeferredWebhook.new("Subscription is not in this app yet")
    end

    def self.each_ready(older_than:, &)
      cutoff = Time.current - older_than
      cursor_at = nil
      cursor_id = nil
      loop do
        rows = ready_batch(cutoff, cursor_at, cursor_id)
        break if rows.empty?

        rows.each(&)
        cursor_at = rows.last.created_at
        cursor_id = rows.last.id
        break if rows.size < BATCH_SIZE
      end
    end

    def self.pending?(webhook)
      webhook&.payload.to_h.dig("invoice", "prices_pending") == true
    end

    def self.older_pending?(webhook, snapshot)
      return false if webhook.blank?

      stripe_subscription_id = snapshot.to_h["subscription"].to_s
      return false if stripe_subscription_id.blank?

      WebhookEvent.where(event_type: "invoice.paid").where.not(id: webhook.id)
                  .where(PENDING_SQL)
                  .where("payload #>> '{invoice,subscription}' = ?", stripe_subscription_id)
                  .where(
                    "created_at < :created_at OR (created_at = :created_at AND id < :id)",
                    created_at: webhook.created_at,
                    id: webhook.id
                  ).exists?
    end

    def self.ready_batch(cutoff, cursor_at, cursor_id)
      scope = WebhookEvent.where(event_type: "invoice.paid").where(created_at: ...cutoff).where(PENDING_SQL)
      if cursor_at
        scope = scope.where(
          "created_at > :created_at OR (created_at = :created_at AND id > :id)",
          created_at: cursor_at,
          id: cursor_id
        )
      end
      scope.order(:created_at, :id).limit(BATCH_SIZE).to_a
    end
    private_class_method :ready_batch, :older_pending?
  end
end
