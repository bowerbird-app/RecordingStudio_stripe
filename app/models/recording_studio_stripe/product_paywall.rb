# frozen_string_literal: true

module RecordingStudioStripe
  class ProductPaywall < ApplicationRecord
    self.table_name = "recording_studio_stripe_product_paywalls"

    belongs_to :product, class_name: "RecordingStudioStripe::Product"
    belongs_to :paywall, class_name: "RecordingStudioStripe::Paywall"

    validates :product_id, uniqueness: { scope: :paywall_id }
  end
end
