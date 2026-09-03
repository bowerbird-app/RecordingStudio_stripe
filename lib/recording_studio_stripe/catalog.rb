# frozen_string_literal: true

module RecordingStudioStripe
  class Catalog
    def self.plan_products
      Product.plans.includes(:prices).order(:name)
    end

    def self.plan_groups
      products = plan_products.to_a
      SubscriptionTypes.keys.map do |key|
        {
          key: key,
          label: SubscriptionTypes.configured? ? SubscriptionTypes.label(key) : nil,
          products: products.select { |product| product.subscription_type == key }
        }
      end
    end

    def self.allowance_prices
      Price.active.one_time.joins(:product).merge(Product.allowances).includes(:product).order(:unit_amount)
    end
  end
end
