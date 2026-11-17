# frozen_string_literal: true

module RecordingStudioStripe
  class AllowancePurchase < ApplicationRecord
    STATUS_ACTIVE = "active"
    STATUS_FAILED = "failed"
    STATUSES = [STATUS_ACTIVE, STATUS_FAILED].freeze

    self.table_name = "recording_studio_stripe_allowance_purchases"

    belongs_to :meter, class_name: "RecordingStudioStripe::Meter"
    belongs_to :customer, class_name: "RecordingStudioStripe::Customer", optional: true
    belongs_to :price, class_name: "RecordingStudioStripe::Price", optional: true

    validates :root_recording_id, presence: true
    validates :quantity, numericality: { greater_than: 0 }
    validates :purchased_at, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :credits_revoked, :credit_shortfall, :refunded_amount,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :credits_revoked_within_quantity

    def failed?
      status == STATUS_FAILED
    end

    def net_quantity
      quantity.to_i - credits_revoked.to_i
    end

    private

    def credits_revoked_within_quantity
      return if credits_revoked.to_i <= quantity.to_i

      errors.add(:credits_revoked, "is above the pack")
    end
  end
end
