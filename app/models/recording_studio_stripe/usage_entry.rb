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
      return validate_priced_credits if breakdown.is_a?(Hash)
      return errors.add(:breakdown, "must be a JSON object") unless breakdown.nil?

      parts = [usage_key.present?, !source_quantity.nil?, !credit_rate.nil?]
      return if parts.none?
      return errors.add(:base, "usage source needs a key, source quantity, and credit rate") unless parts.all?
      return errors.add(:base, "source quantity and credit rate must be positive integers") unless positive_source?

      return if quantity.to_i == source_quantity * credit_rate

      errors.add(:quantity, "must equal source quantity times credit rate")
    end

    def validate_priced_credits
      errors.add(:base, "credit breakdown belongs on the credits meter") unless meter&.name == "credits"
      errors.add(:base, "credit breakdown needs a usage key") if usage_key.blank?
      errors.add(:base, "credit breakdown cannot include a tariff") unless source_quantity.nil? && credit_rate.nil?
      errors.add(:breakdown, "is too large") if breakdown_too_large?
    end

    def breakdown_too_large?
      JSON.generate(breakdown).bytesize > CreditBreakdown::MAX_BYTES
    rescue JSON::GeneratorError
      true
    end

    def positive_source?
      source_quantity.is_a?(Integer) && source_quantity.positive? &&
        credit_rate.is_a?(Integer) && credit_rate.positive?
    end
  end
end
