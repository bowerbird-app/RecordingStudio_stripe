# frozen_string_literal: true

module RecordingStudioStripe
  class AllowancePurchase < ApplicationRecord
    self.table_name = "recording_studio_stripe_allowance_purchases"

    belongs_to :meter, class_name: "RecordingStudioStripe::Meter"
    belongs_to :customer, class_name: "RecordingStudioStripe::Customer", optional: true
    belongs_to :price, class_name: "RecordingStudioStripe::Price", optional: true

    validates :root_recording_id, presence: true
    validates :quantity, numericality: { greater_than: 0 }
    validates :purchased_at, presence: true
  end
end
