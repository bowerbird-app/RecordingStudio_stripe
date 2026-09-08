# frozen_string_literal: true

require "test_helper"

class PlanChangeTest < Minitest::Test
  ProductStub = Struct.new(:name, :id, keyword_init: true)
  PriceStub = Struct.new(:id, :product, :product_id, :interval, :unit_amount, :metadata, :formatted_amount,
                         keyword_init: true) do
    def monthly?
      interval == "month"
    end

    def annual?
      interval == "year"
    end

    def monthly_unit_amount
      return unit_amount if monthly? || interval.blank?
      return (unit_amount.to_f / 12).round if annual?

      unit_amount
    end
  end
  SubscriptionStub = Struct.new(:price, :current_period_end, keyword_init: true)

  def test_upgrade_copy_names_the_new_plan_and_the_charge
    change = PlanChangeTest.change(from_amount: 900, to_amount: 2900, from_name: "Starter", to_name: "Pro")

    assert change.upgrade?
    assert_equal "Upgrade to Pro?", change.title
    assert_equal "You pay the difference today.", change.subtitle
    assert_equal "Upgrade", change.confirm_label
    assert_equal "Next", change.next_badge
  end

  def test_downgrade_copy_names_when_the_cheaper_plan_starts
    change = PlanChangeTest.change(
      from_amount: 2900,
      to_amount: 900,
      from_name: "Pro",
      to_name: "Starter",
      period_end: Date.new(2026, 10, 12)
    )

    assert change.downgrade?
    assert_equal "Switch to Starter?", change.title
    assert_equal "Starter starts on October 12, 2026. You keep Pro until then.", change.subtitle
    assert_equal "Switch at renewal", change.confirm_label
    assert_equal "From renewal", change.next_badge
  end

  def test_same_product_interval_switch_names_the_cadence
    starter = ProductStub.new(name: "Pro", id: "pro")
    monthly = PriceStub.new(id: "m", product: starter, product_id: "pro", interval: "month", unit_amount: 2900,
                            metadata: {}, formatted_amount: "$29")
    yearly = PriceStub.new(id: "y", product: starter, product_id: "pro", interval: "year", unit_amount: 29_000,
                           metadata: {}, formatted_amount: "$290")
    subscription = SubscriptionStub.new(price: monthly, current_period_end: nil)
    change = RecordingStudioStripe::PlanChange.new(subscription: subscription, price: yearly)

    assert change.upgrade?
    assert_equal "Switch Pro to yearly?", change.title
  end

  def self.change(from_amount:, to_amount:, from_name:, to_name:, period_end: nil)
    from_product = ProductStub.new(name: from_name, id: from_name.downcase)
    to_product = ProductStub.new(name: to_name, id: to_name.downcase)
    from_price = PriceStub.new(id: "from", product: from_product, product_id: from_product.id, interval: "month",
                               unit_amount: from_amount, metadata: {}, formatted_amount: "$#{from_amount / 100}")
    to_price = PriceStub.new(id: "to", product: to_product, product_id: to_product.id, interval: "month",
                             unit_amount: to_amount, metadata: {}, formatted_amount: "$#{to_amount / 100}")
    subscription = SubscriptionStub.new(price: from_price, current_period_end: period_end)
    RecordingStudioStripe::PlanChange.new(subscription: subscription, price: to_price)
  end
end
