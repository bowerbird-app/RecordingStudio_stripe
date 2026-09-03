# frozen_string_literal: true

module RecordingStudioStripe
  class Product < ApplicationRecord
    self.table_name = "recording_studio_stripe_products"

    KINDS = %w[plan allowance].freeze

    has_many :prices, class_name: "RecordingStudioStripe::Price", dependent: :destroy
    has_many :product_paywalls, class_name: "RecordingStudioStripe::ProductPaywall", dependent: :delete_all
    has_many :paywalls, through: :product_paywalls, class_name: "RecordingStudioStripe::Paywall"

    validates :stripe_id, presence: true, uniqueness: true
    validates :name, presence: true
    validates :kind, inclusion: { in: KINDS }
    validates :subscription_type, presence: true
    validates :subscription_type, inclusion: { in: ->(_) { SubscriptionTypes.keys } }, if: :plan?

    before_validation :assign_default_subscription_type

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

    def assign_paywalls(names)
      return if allowance?

      selected = Array(names).map(&:to_s).reject(&:blank?)
      self.paywalls = Paywall.where(name: selected)
    end

    def opens_labels
      paywalls.order(:name).map(&:label)
    end

    def subscription_type_label
      SubscriptionTypes.label(subscription_type)
    end

    private

    def assign_default_subscription_type
      self.subscription_type = subscription_type.presence || SubscriptionTypes.keys.first
    end
  end
end
