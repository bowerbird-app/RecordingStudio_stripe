# frozen_string_literal: true

module RecordingStudioStripe
  class Catalog
    def self.plan_products
      sorted_plans(Product.plans.includes(:prices))
    end

    def self.plan_groups
      products = plan_products
      SubscriptionTypes.keys.map do |key|
        {
          key: key,
          label: SubscriptionTypes.configured? ? SubscriptionTypes.label(key) : nil,
          products: products.select { |product| product.subscription_type == key }
        }
      end
    end

    def self.sorted_plans(products, interval: "month")
      Array(products).sort_by { |product| plan_amount(product, interval) }
    end

    def self.allowance_prices
      Price.active.one_time.joins(:product).merge(Product.allowances).includes(:product).order(:unit_amount)
    end

    def self.plan_amount(product, interval)
      price = interval.to_s == "year" ? product.annual_price : product.monthly_price
      price&.unit_amount || Float::INFINITY
    end
    private_class_method :plan_amount
  end
end
