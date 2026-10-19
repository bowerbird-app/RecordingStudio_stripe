# frozen_string_literal: true

module RecordingStudioStripe
  # Provider-neutral events for other gems. Names follow ActiveSupport::Notifications:
  # "trial_started.recording_studio_stripe" and "invoice_paid.recording_studio_stripe".
  module DomainEvents
    SCHEMA_VERSION = 1
    TRIAL_STARTED = "trial_started.recording_studio_stripe"
    INVOICE_PAID = "invoice_paid.recording_studio_stripe"
    NAMES = {
      "trial_started" => TRIAL_STARTED,
      "invoice_paid" => INVOICE_PAID
    }.freeze
    WEBHOOK_KEY = :recording_studio_stripe_domain_webhook

    class << self
      def notification_name(name)
        NAMES.fetch(name)
      end

      def with_webhook(webhook)
        previous = current_webhook
        self.current_webhook = webhook
        yield
      ensure
        self.current_webhook = previous
      end

      def remember_subscription!(status:, stripe_subscription_id:)
        webhook = current_webhook
        return if webhook.blank? || status.blank?

        webhook.update!(
          payload: webhook.payload.merge(
            "subscription_status" => status.to_s,
            "stripe_subscription_id" => stripe_subscription_id.to_s
          )
        )
      end

      def record_trial_started!(subscription)
        return unless subscription&.trialing?
        return unless events_table?

        create_event(
          name: "trial_started",
          idempotency_key: "trial_started/#{subscription.id}",
          subscription: subscription,
          payload: {}
        )
      end

      def record_invoice_paid!(subscription)
        return unless events_table?
        return if subscription.blank?

        snapshot = invoice_snapshot
        return if skip_invoice?(snapshot)

        subscription.with_lock do
          held = PricesPending.waiting?(current_webhook, snapshot)
          held ||= PricesPending.hold_for_older?(current_webhook, snapshot)
          return if held

          create_invoice_event(subscription, snapshot)
        end
      end

      def replay(webhook_event)
        ApplicationRecord.transaction do
          with_webhook(webhook_event) do
            rebuild_invoice(webhook_event)
            rebuild_trial(webhook_event)
          end
        end
        ActiveRecord.after_all_transactions_commit { publish_unpublished(webhook_event) }
      end

      def publish_pending!(older_than:)
        return unless events_table?

        DomainEvent.publish_pending!(older_than: older_than)
        PricesPending.each_ready(older_than: older_than) do |webhook|
          replay(webhook)
        rescue StandardError => e
          report_handled(e, context: { webhook_id: webhook.id })
        end
      end

      def report_handled(error, context: {})
        return unless defined?(Rails) && Rails.respond_to?(:error) && Rails.error

        Rails.error.report(error, handled: true, context: context)
      end

      def events_table?
        DomainEvent.table_exists?
      rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
        false
      end

      private

      def current_webhook
        ActiveSupport::IsolatedExecutionState[WEBHOOK_KEY]
      end

      def current_webhook=(webhook)
        ActiveSupport::IsolatedExecutionState[WEBHOOK_KEY] = webhook
      end

      def occurred_at
        created = current_webhook&.payload.to_h["created"]
        return Time.zone.at(created.to_i) if created.present?

        Time.current
      end

      def invoice_snapshot
        current_webhook&.payload.to_h["invoice"]
      end

      def skip_invoice?(snapshot)
        snapshot.blank? || snapshot["trial_fee"] || snapshot["amount_paid"].to_i.zero? || snapshot["invoice_id"].blank?
      end

      def create_invoice_event(subscription, snapshot)
        invoice_id = snapshot["invoice_id"].to_s
        return if invoice_id.blank?

        create_event(
          name: "invoice_paid",
          idempotency_key: "invoice_paid/#{invoice_id}",
          subscription: subscription,
          payload: invoice_payload(subscription, snapshot, invoice_id)
        )
      end

      def invoice_payload(subscription, snapshot, invoice_id)
        {
          "amount" => snapshot["amount_paid"],
          "currency" => snapshot["currency"],
          "invoice_id" => invoice_id,
          "billing_reason" => snapshot["billing_reason"].to_s,
          "subscription_status" => subscription.status.to_s,
          "first_payment" => InvoicePayment.first?(subscription, snapshot)
        }
      end

      def create_event(name:, idempotency_key:, subscription:, payload:)
        # Unique index is the lock. A uniqueness validation would raise RecordInvalid
        # before create_or_find_by! can rescue the database conflict in a savepoint.
        DomainEvent.create_or_find_by!(idempotency_key: idempotency_key) do |event|
          event.name = name
          event.subscription = subscription
          event.customer_id = subscription.customer_id
          event.root_recording_id = subscription.root_recording_id
          event.webhook_event = current_webhook
          event.occurred_at = occurred_at
          event.payload = payload
        end
      end

      def rebuild_invoice(webhook_event)
        return unless webhook_event.event_type == "invoice.paid"

        PricesPending.alert!(webhook_event)
        PricesPending.report_missing_subscription!(webhook_event)
        PricesPending.refresh!(webhook_event)
        return if skip_invoice?(invoice_snapshot)
        return if invoice_snapshot.to_h["prices_pending"] == true

        subscription = Subscription.find_by(stripe_id: invoice_snapshot["subscription"])
        record_invoice_paid!(subscription) if subscription
      end

      def rebuild_trial(webhook_event)
        return unless webhook_event.payload.to_h["subscription_status"] == "trialing"

        record_trial_started!(Subscription.find_by(stripe_id: trial_stripe_id(webhook_event)))
      end

      def trial_stripe_id(webhook_event)
        payload = webhook_event.payload.to_h
        return payload["stripe_subscription_id"] if webhook_event.event_type.to_s.start_with?("checkout.")

        payload["stripe_subscription_id"].presence || payload["object_id"]
      end

      def publish_unpublished(webhook_event)
        DomainEvent.where(webhook_event_id: webhook_event.id, published_at: nil).find_each(&:publish!)
      end
    end
  end
end
