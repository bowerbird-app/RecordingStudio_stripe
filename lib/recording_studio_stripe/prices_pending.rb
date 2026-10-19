# frozen_string_literal: true

module RecordingStudioStripe
  # A positive invoice whose Price is not in the catalogue yet. The webhook
  # stays stored, and the pending sweep emits invoice_paid after the Price syncs.
  class PricesPending
    BATCH_SIZE = 100
    # Same predicate as idx_rs_stripe_webhook_events_prices_pending, so the
    # planner can prove the partial index applies.
    PENDING_SQL = "event_type = 'invoice.paid' AND (payload #>> '{invoice,prices_pending}') = 'true'"
    MARKERS = %w[prices_pending_alerted_at missing_subscription_reported_at].freeze

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
      return if webhook.blank?

      webhook.with_lock do
        webhook.reload
        snapshot = webhook.payload.to_h["invoice"]
        next if snapshot.blank? || snapshot["prices_pending"] != true

        refreshed = InvoiceSnapshot.refresh(snapshot)
        refreshed["prices_pending"] = true if older_pending?(webhook, refreshed)
        webhook.update!(payload: webhook.payload.merge("invoice" => refreshed))
      end
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

    def self.report_missing_subscription!(webhook)
      error = missing_subscription(webhook)
      return if error.blank?
      return unless claim_marker!(webhook, "missing_subscription_reported_at") == 1

      schedule_report(webhook, error)
    end

    # A Price that never syncs is reported once, then left pending.
    # The claim is a conditional update, and the report waits until commit.
    def self.alert!(webhook)
      return unless pending?(webhook)
      return unless InvoiceSnapshot.missing_prices?(webhook.payload.to_h["invoice"])
      return if webhook.created_at >= Time.current - alert_after
      return unless claim_marker!(webhook, "prices_pending_alerted_at") == 1

      schedule_report(webhook, DeferredWebhook.new("Invoice is still waiting on a Price"))
    end

    # Manual escape. Clears the flag under the row lock and reports after commit.
    # Does not emit invoice_paid. Replaying a released webhook whose Price is still
    # missing marks it prices_pending again.
    def self.release!(webhook)
      return if webhook.blank?

      released = webhook.with_lock do
        webhook.reload
        next false unless pending?(webhook)

        invoice = webhook.payload.to_h["invoice"].to_h.merge("prices_pending" => false)
        webhook.update!(payload: webhook.payload.merge("invoice" => invoice))
        true
      end
      return unless released

      schedule_report(webhook, DeferredWebhook.new("Released a prices_pending invoice without emitting"))
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

    def self.alerted?(webhook)
      marker?(webhook, "prices_pending_alerted_at")
    end

    def self.missing_subscription_reported?(webhook)
      marker?(webhook, "missing_subscription_reported_at")
    end

    def self.older_pending?(webhook, snapshot)
      return false if webhook.blank?

      stripe_subscription_id = snapshot.to_h["subscription"].to_s
      return false if stripe_subscription_id.blank?

      WebhookEvent.where.not(id: webhook.id)
                  .where(PENDING_SQL)
                  .where("payload #>> '{invoice,subscription}' = ?", stripe_subscription_id)
                  .where(created_at: hold_cutoff..)
                  .where(
                    "created_at < :created_at OR (created_at = :created_at AND id < :id)",
                    created_at: webhook.created_at,
                    id: webhook.id
                  ).exists?
    end

    def self.ready_batch(cutoff, cursor_at, cursor_id)
      scope = WebhookEvent.where(created_at: ...cutoff).where(PENDING_SQL)
      if cursor_at
        scope = scope.where(
          "created_at > :created_at OR (created_at = :created_at AND id > :id)",
          created_at: cursor_at,
          id: cursor_id
        )
      end
      scope.order(:created_at, :id).limit(BATCH_SIZE).to_a
    end

    def self.claim_marker!(webhook, key)
      return 0 if webhook.blank? || MARKERS.exclude?(key)

      path = "{invoice,#{key}}"
      claimed = WebhookEvent.where(id: webhook.id).where("payload #>> ? IS NULL", path).update_all(
        ["payload = jsonb_set(payload, ?::text[], to_jsonb(?::text), true)", path, Time.current.iso8601]
      )
      webhook.reload if claimed == 1
      claimed
    end

    def self.schedule_report(webhook, error)
      webhook_id = webhook.id
      ActiveRecord.after_all_transactions_commit do
        DomainEvents.report_handled(error, context: { webhook_id: webhook_id })
      end
    end

    def self.marker?(webhook, key)
      webhook&.payload.to_h.dig("invoice", key).present?
    end

    def self.alert_after
      RecordingStudioStripe.configuration.prices_pending_alert_after
    end

    def self.hold_cutoff
      Time.current - RecordingStudioStripe.configuration.prices_pending_max_hold
    end
    private_class_method :ready_batch, :older_pending?, :claim_marker!, :schedule_report
    private_class_method :marker?, :alert_after, :hold_cutoff
  end
end
