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

    def self.publish_pending!(older_than:)
      cutoff = Time.current - older_than
      where(published_at: nil).where(created_at: ...cutoff).find_each(&:publish!)
    end

    # Claim, then notify. A subscriber error clears the claim so a later sweep can retry.
    # Delivery is at-least-once. Subscribers dedupe on payload[:id].
    def publish!
      return if published_at.present?
      return unless claimed_publish?

      ActiveSupport::Notifications.instrument(DomainEvents.notification_name(name), instrument_payload)
    rescue StandardError => e
      release_publish_claim!
      DomainEvents.report_publish_failure(e)
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

    def claimed_publish?
      self.class.where(id: id, published_at: nil).update_all(published_at: Time.current) == 1
    end

    def release_publish_claim!
      self.class.where(id: id).update_all(published_at: nil)
      self.published_at = nil
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
