# frozen_string_literal: true

module RecordingStudioStripe
  class UsageEntry < ApplicationRecord
    self.table_name = "recording_studio_stripe_usage_entries"

    belongs_to :meter, class_name: "RecordingStudioStripe::Meter"

    validates :root_recording_id, presence: true
    validates :quantity, numericality: { greater_than: 0 }
    validates :recorded_at, presence: true
  end
end
