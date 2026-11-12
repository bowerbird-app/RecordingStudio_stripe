# frozen_string_literal: true

require "test_helper"

class CreditRatesTest < ActiveSupport::TestCase
  setup do
    @suffix = SecureRandom.hex(4)
  end

  test "cents per credit uses the price amount and that period's credits" do
    monthly = plan_price(name: "Month #{@suffix}", interval: "month", unit_amount: 2_900, credits: 1_000)
    annual = plan_price(name: "Year #{@suffix}", interval: "year", unit_amount: 120_000, credits: 10_000)
    pack = pack_price(name: "Pack #{@suffix}", unit_amount: 1_000, allowance: 5_000)
    plan_price(name: "Week #{@suffix}", interval: "week", unit_amount: 700, credits: 100, currency: "eur")

    rows = rows_for(@suffix)
    usd = rows.select { |row| row.currency == "USD" }
    eur = rows.select { |row| row.currency == "EUR" }

    assert_equal [pack.name, monthly.name, annual.name], usd.map(&:product_name)
    assert_equal Rational(1, 5), usd[0].cents_per_credit
    assert_equal Rational(29, 10), usd[1].cents_per_credit
    assert_equal Rational(12, 1), usd[2].cents_per_credit
    assert usd[0].cheapest
    refute usd[1].cheapest
    refute usd[2].cheapest
    assert_equal "Assumes the whole price is for credits.", usd[1].note
    assert_equal "—", usd[0].note
    assert eur.fetch(0).cheapest
    assert_equal Rational(7, 1), eur.fetch(0).cents_per_credit
  end

  test "a tie for cheapest is marked on each currency winner" do
    pack_price(name: "Tie A #{@suffix}", unit_amount: 500, allowance: 1_000)
    pack_price(name: "Tie B #{@suffix}", unit_amount: 1_000, allowance: 2_000)

    usd = rows_for(@suffix).select { |row| row.currency == "USD" }

    assert_equal 2, usd.count(&:cheapest)
    assert_equal [Rational(1, 2), Rational(1, 2)], usd.map(&:cents_per_credit)
  end

  test "trial, free, empty, and inactive prices are left out" do
    plan_price(name: "Live #{@suffix}", interval: "month", unit_amount: 1_000, credits: 100)
    plan_price(name: "Free #{@suffix}", interval: "month", unit_amount: 0, credits: 100)
    plan_price(name: "No credits #{@suffix}", interval: "month", unit_amount: 1_000, credits: nil)
    plan_price(name: "Paused #{@suffix}", interval: "month", unit_amount: 1_000, credits: 100, active: false)
    plan_price(name: "Archived product #{@suffix}", interval: "month", unit_amount: 1_000, credits: 100,
               product_active: false)
    plan_price(name: "Trial kind #{@suffix}", interval: "month", unit_amount: 1_000, credits: 100,
               extra: { "kind" => "trial" })
    fee = plan_price(name: "Trial fee #{@suffix}", interval: nil, unit_amount: 100, credits: 10,
                     kind: "allowance", extra: { "kind" => "trial_fee", "meter" => "credits", "allowance" => "10" })
    pack_price(name: "Calls #{@suffix}", unit_amount: 1_000, allowance: 50, meter: "api_calls")
    plan_price(name: "One-time plan #{@suffix}", interval: nil, unit_amount: 1_000, credits: 100)

    names = rows_for(@suffix).map(&:product_name)

    assert_includes names, "Live #{@suffix}"
    refute_includes names, "Free #{@suffix}"
    refute_includes names, "No credits #{@suffix}"
    refute_includes names, "Paused #{@suffix}"
    refute_includes names, "Archived product #{@suffix}"
    refute_includes names, "Trial kind #{@suffix}"
    refute_includes names, fee.name
    refute_includes names, "Calls #{@suffix}"
    refute_includes names, "One-time plan #{@suffix}"
  end

  private

  def rows_for(suffix)
    RecordingStudioStripe::CreditRates.rows.select { |row| row.product_name.include?(suffix) }
  end

  def plan_price(name:, interval:, unit_amount:, credits:, currency: "usd", active: true, product_active: true,
                 kind: "plan", extra: {})
    product = RecordingStudioStripe::Product.create!(
      stripe_id: "prod_#{SecureRandom.hex(6)}",
      name: name,
      kind: kind,
      active: product_active,
      subscription_type: "studio"
    )
    metadata = extra.dup
    metadata["included_credits"] = credits.to_s if credits && kind == "plan" && interval.present?
    RecordingStudioStripe::Price.create!(
      stripe_id: "price_#{SecureRandom.hex(6)}",
      product: product,
      unit_amount: unit_amount,
      currency: currency,
      interval: interval,
      active: active,
      metadata: metadata
    )
    product
  end

  def pack_price(name:, unit_amount:, allowance:, meter: "credits", currency: "usd")
    product = RecordingStudioStripe::Product.create!(
      stripe_id: "prod_#{SecureRandom.hex(6)}",
      name: name,
      kind: "allowance",
      active: true,
      subscription_type: "studio"
    )
    RecordingStudioStripe::Price.create!(
      stripe_id: "price_#{SecureRandom.hex(6)}",
      product: product,
      unit_amount: unit_amount,
      currency: currency,
      interval: nil,
      active: true,
      metadata: { "meter" => meter, "allowance" => allowance.to_s }
    )
    product
  end
end
