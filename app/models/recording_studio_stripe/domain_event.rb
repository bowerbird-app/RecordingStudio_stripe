# frozen_string_literal: true

module RecordingStudioStripe
  class DomainEvent < ApplicationRecord
    self.table_name = "recording_studio_stripe_domain_events"

    belongs_to :subscription, class_name: "RecordingStudioStripe::Subscription"
    belongs_to :webhook_event, class_name: "RecordingStudioStripe::WebhookEvent", optional: true

    validates :name, presence: true, inclusion: { in: DomainEvents::NAMES.keys }
    validates :idempotency_key, presence: true
    validates :occurred_at, presence: true
    validates :customer_id, presence: true
    validates :root_recording_id, presence: true

    after_commit :publish!, on: :create

    def self.publish_lease
      RecordingStudioStripe.configuration.domain_event_publish_lease
    end

    def self.publish_pending!(older_than:)
      cutoff = Time.current - older_than
      where(published_at: nil).where(created_at: ...cutoff).where(lease_sql, Time.current - publish_lease)
                              .find_each(&:publish!)
    end

    def self.lease_sql
      "publish_claimed_at IS NULL OR publish_claimed_at < ?"
    end

    # Lease the row, then notify. published_at is set only after instrument returns.
    # A crash while notifying leaves the lease so a later sweep can retry.
    # A subscriber error clears the lease. Delivery is at-least-once.
    # Subscribers dedupe on payload[:id].
    def publish!
      return if published_at.present?
      return unless claimed_publish?
      return unless deliver_notification

      mark_published!
    end

    def instrument_payload
      {
        schema_version: DomainEvents::SCHEMA_VERSION,
        id: id,
        occurred_at: occurred_at,
        subscription_id: subscription_id,
        customer_id: customer_id,
        root_recording_id: root_recording_id
      }.merge(extra_payload)
    end

    private

    def deliver_notification
      ActiveSupport::Notifications.instrument(DomainEvents.notification_name(name), instrument_payload)
      true
    rescue StandardError => e
      release_publish_claim!
      DomainEvents.report_publish_failure(e, context: { publish_attempts: publish_attempts })
      false
    end

    def claimed_publish?
      now = Time.current
      claimed = self.class.where(id: id, published_at: nil)
                    .where(self.class.lease_sql, now - self.class.publish_lease)
                    .update_all(publish_claimed_at: now) == 1
      self.publish_claimed_at = now if claimed
      claimed
    end

    def mark_published!
      now = Time.current
      self.class.where(id: id).update_all(published_at: now, publish_claimed_at: nil)
      self.published_at = now
      self.publish_claimed_at = nil
    end

    def release_publish_claim!
      self.class.where(id: id, published_at: nil).update_all(
        "publish_claimed_at = NULL, publish_attempts = publish_attempts + 1"
      )
      self.publish_claimed_at = nil
      self.publish_attempts = publish_attempts.to_i + 1
    end

    def extra_payload
      extras = payload.to_h.symbolize_keys
      extras[:amount] = extras[:amount].to_i unless extras[:amount].nil?
      return extras unless extras.key?(:first_payment)

      extras[:first_payment] = ActiveModel::Type::Boolean.new.cast(extras[:first_payment])
      extras
    end
  end
end
