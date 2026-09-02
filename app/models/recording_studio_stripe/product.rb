# frozen_string_literal: true

module RecordingStudioStripe
  class Product < ApplicationRecord
    self.table_name = "recording_studio_stripe_products"

    KINDS = %w[plan allowance].freeze

    has_many :prices, class_name: "RecordingStudioStripe::Price", dependent: :destroy

    validates :stripe_id, presence: true, uniqueness: true
    validates :name, presence: true
    validates :kind, inclusion: { in: KINDS }

    scope :plans, -> { where(kind: "plan", active: true) }
    scope :allowances, -> { where(kind: "allowance", active: true) }
    scope :active, -> { where(active: true) }

    def plan?
      kind == "plan"
    end

    def allowance?
      kind == "allowance"
    end

    def monthly_price
      prices.active.recurring.find_by(interval: "month")
    end

    def annual_price
      prices.active.recurring.find_by(interval: "year")
    end
  end
end
