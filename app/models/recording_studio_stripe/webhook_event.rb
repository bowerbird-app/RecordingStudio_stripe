# frozen_string_literal: true

module RecordingStudioStripe
  class WebhookEvent < ApplicationRecord
    self.table_name = "recording_studio_stripe_webhook_events"

    validates :stripe_id, presence: true, uniqueness: true
    validates :event_type, presence: true
  end
end
