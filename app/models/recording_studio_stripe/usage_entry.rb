# frozen_string_literal: true

module RecordingStudioStripe
  class UsageEntry < ApplicationRecord
    self.table_name = "recording_studio_stripe_usage_entries"

    belongs_to :meter, class_name: "RecordingStudioStripe::Meter"

    validates :root_recording_id, presence: true
    validates :quantity, numericality: { greater_than: 0 }
    validates :recorded_at, presence: true
    validate :credit_source_matches_quantity

    private

    def credit_source_matches_quantity
      parts = [usage_key.present?, !source_quantity.nil?, !credit_rate.nil?]
      return if parts.none?
      return errors.add(:base, "usage source needs a key, source quantity, and credit rate") unless parts.all?
      return errors.add(:base, "source quantity and credit rate must be positive integers") unless positive_source?

      return if quantity.to_i == source_quantity * credit_rate

      errors.add(:quantity, "must equal source quantity times credit rate")
    end

    def positive_source?
      source_quantity.is_a?(Integer) && source_quantity.positive? &&
        credit_rate.is_a?(Integer) && credit_rate.positive?
    end
  end
end
