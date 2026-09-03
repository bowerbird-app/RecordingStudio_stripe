# frozen_string_literal: true

module RecordingStudioStripe
  class Subscription < ApplicationRecord
    self.table_name = "recording_studio_stripe_subscriptions"

    ACTIVE_STATUSES = %w[active trialing past_due].freeze

    belongs_to :customer, class_name: "RecordingStudioStripe::Customer"
    belongs_to :price, class_name: "RecordingStudioStripe::Price", optional: true
    belongs_to :scheduled_price, class_name: "RecordingStudioStripe::Price", optional: true

    validates :stripe_id, presence: true, uniqueness: true
    validates :root_recording_id, presence: true
    validates :status, presence: true

    scope :current, -> { where(status: ACTIVE_STATUSES) }

    def self.current_for(root_recording_id:)
      current.where(root_recording_id: root_recording_id).order(updated_at: :desc).first
    end

    def active?
      ACTIVE_STATUSES.include?(status)
    end

    def canceling?
      cancel_at_period_end?
    end

    def scheduled_downgrade?
      scheduled_price_id.present? && scheduled_price_id != price_id
    end
  end
end
