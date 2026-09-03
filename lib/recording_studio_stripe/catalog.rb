# frozen_string_literal: true

module RecordingStudioStripe
  class Catalog
    def self.plan_products
      Product.plans.includes(:prices).order(:name)
    end

    def self.allowance_prices
      Price.active.one_time.joins(:product).merge(Product.allowances).includes(:product).order(:unit_amount)
    end
  end
end
