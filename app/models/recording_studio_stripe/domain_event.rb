# frozen_string_literal: true

module RecordingStudioStripe
  class DomainEvent < ApplicationRecord
    self.table_name = "recording_studio_stripe_domain_events"

    belongs_to :subscription, class_name: "RecordingStudioStripe::Subscription"
    belongs_to :webhook_event, class_name: "RecordingStudioStripe::WebhookEvent", optional: true

    validates :name, presence: true, inclusion: { in: DomainEvents::NAMES.keys }
    validates :idempotency_key, presence: true, uniqueness: true
    validates :occurred_at, presence: true
    validates :customer_id, presence: true
    validates :root_recording_id, presence: true

    after_commit :publish!, on: :create

    def publish!
      return if published_at.present?

      ActiveSupport::Notifications.instrument(DomainEvents.notification_name(name), instrument_payload)
      update_column(:published_at, Time.current)
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

    def extra_payload
      extras = payload.to_h.symbolize_keys
      extras[:amount] = extras[:amount].to_i unless extras[:amount].nil?
      return extras unless extras.key?(:first_payment)

      extras[:first_payment] = ActiveModel::Type::Boolean.new.cast(extras[:first_payment])
      extras
    end
  end
end
