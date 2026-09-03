# frozen_string_literal: true

module RecordingStudioStripe
  class Price < ApplicationRecord
    self.table_name = "recording_studio_stripe_prices"

    belongs_to :product, class_name: "RecordingStudioStripe::Product"

    validates :stripe_id, presence: true, uniqueness: true
    validates :currency, presence: true
    validates :unit_amount, numericality: { greater_than_or_equal_to: 0 }

    scope :active, -> { where(active: true) }
    scope :recurring, -> { where.not(interval: nil) }
    scope :one_time, -> { where(interval: nil) }

    def recurring?
      interval.present?
    end

    def monthly?
      interval == "month"
    end

    def annual?
      interval == "year"
    end

    def included_quantity(meter_name)
      (metadata || {})["included_#{meter_name}"].to_i
    end

    def allowance_meter_name
      (metadata || {})["meter"]
    end

    def allowance_quantity
      (metadata || {})["allowance"].to_i
    end

    def monthly_unit_amount
      return unit_amount if monthly? || interval.blank?
      return (unit_amount.to_f / 12).round if annual?

      unit_amount
    end

    def formatted_amount
      amount = unit_amount.to_i / 100.0
      symbol = currency.to_s.upcase == "USD" ? "$" : "#{currency.to_s.upcase} "
      formatted = format("%.0f", amount)
      formatted = format("%.2f", amount) unless amount == amount.to_i
      "#{symbol}#{formatted}"
    end
  end
end
