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

    def limit_quantity(name)
      (metadata || {})["limit_#{name}"].to_i
    end

    def assign_limits(quantities)
      return if allowance?
      return if quantities.nil?

      self.metadata = merge_limit_metadata(quantities)
    end

    def plan_card_settings
      raw = (metadata || {})["plan_card"]
      return {} unless raw.is_a?(Hash)

      raw.stringify_keys
    end

    def assign_plan_card(settings)
      return if allowance?
      return if settings.nil?

      self.metadata = (metadata || {}).stringify_keys.merge("plan_card" => PlanCardSettings.normalize(settings))
    end

    def limit_inclusion_lines
      Limits.for_subscription_type(subscription_type).filter_map do |definition|
        quantity = limit_quantity(definition.name)
        next if quantity <= 0

        "#{quantity} #{definition.label.downcase}"
      end
    end

    def limit_metadata
      Limits.keys.each_with_object({}) do |name, data|
        quantity = limit_quantity(name)
        data["limit_#{name}"] = quantity.to_s if quantity.positive?
      end
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

    def merge_limit_metadata(quantities)
      data = (metadata || {}).stringify_keys
      quantities.to_h.stringify_keys.each do |name, value|
        apply_limit_metadata(data, name, value)
      end
      data
    end

    def apply_limit_metadata(data, name, value)
      return unless Limits.known?(name)
      return unless Limits.fetch(name).subscription_type == subscription_type

      key = "limit_#{name}"
      if value.blank?
        data.delete(key)
      else
        data[key] = value.to_i.to_s
      end
    end
  end
end
