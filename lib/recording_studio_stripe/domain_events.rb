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

      def record_trial_started!(subscription)
        return unless subscription&.trialing?

        create_event(
          name: "trial_started",
          idempotency_key: "trial_started/#{subscription.id}",
          subscription: subscription,
          payload: {}
        )
      end

      def record_invoice_paid!(subscription)
        snapshot = invoice_snapshot
        return if snapshot.blank? || snapshot["trial_fee"]

        subscription.with_lock { create_invoice_event(subscription, snapshot) }
      end

      def replay(webhook_event)
        ApplicationRecord.transaction do
          with_webhook(webhook_event) do
            rebuild_invoice(webhook_event)
            rebuild_trial(webhook_event)
          end
        end
        publish_unpublished(webhook_event)
      end

      private

      def current_webhook
        Thread.current[:recording_studio_stripe_domain_webhook]
      end

      def current_webhook=(webhook)
        Thread.current[:recording_studio_stripe_domain_webhook] = webhook
      end

      def occurred_at
        created = current_webhook&.payload.to_h["created"]
        return Time.zone.at(created.to_i) if created.present?

        Time.current
      end

      def invoice_snapshot
        current_webhook&.payload.to_h["invoice"]
      end

      def create_invoice_event(subscription, snapshot)
        invoice_id = snapshot["invoice_id"].to_s
        existing = DomainEvent.find_by(idempotency_key: "invoice_paid/#{invoice_id}")
        return existing if existing

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
          "first_payment" => first_payment?(subscription)
        }
      end

      def first_payment?(subscription)
        !DomainEvent.exists?(subscription_id: subscription.id, name: "invoice_paid")
      end

      def create_event(name:, idempotency_key:, subscription:, payload:)
        existing = DomainEvent.find_by(idempotency_key: idempotency_key)
        return existing if existing

        DomainEvent.create!(
          name: name,
          idempotency_key: idempotency_key,
          subscription: subscription,
          customer_id: subscription.customer_id,
          root_recording_id: subscription.root_recording_id,
          webhook_event: current_webhook,
          occurred_at: occurred_at,
          payload: payload
        )
      rescue ActiveRecord::RecordNotUnique
        DomainEvent.find_by!(idempotency_key: idempotency_key)
      end

      def rebuild_invoice(webhook_event)
        return unless webhook_event.event_type == "invoice.paid"
        return if invoice_snapshot.blank? || invoice_snapshot["trial_fee"]

        subscription = Subscription.find_by(stripe_id: invoice_snapshot["subscription"])
        record_invoice_paid!(subscription) if subscription
      end

      def rebuild_trial(webhook_event)
        return unless webhook_event.payload.to_h["subscription_status"] == "trialing"

        subscription = Subscription.find_by(stripe_id: trial_stripe_id(webhook_event))
        record_trial_started!(subscription)
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
