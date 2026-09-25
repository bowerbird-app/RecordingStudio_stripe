# frozen_string_literal: true

require "test_helper"

class ComparePricesTest < Minitest::Test
  PriceStub = Struct.new(:unit_amount, :interval, :metadata, :product_id, keyword_init: true) do
    def monthly?
      interval == "month"
    end

    def annual?
      interval == "year"
    end

    def weekly?
      interval == "week"
    end

    def monthly_unit_amount
      return unit_amount if monthly? || interval.blank?
      return (unit_amount.to_f / 12).round if annual?
      return (unit_amount.to_f * 52 / 12).round if weekly?

      unit_amount
    end
  end

  def test_higher_monthly_amount_is_an_upgrade
    starter = PriceStub.new(unit_amount: 900, interval: "month", metadata: {}, product_id: "starter")
    pro = PriceStub.new(unit_amount: 2900, interval: "month", metadata: {}, product_id: "pro")

    assert RecordingStudioStripe::ComparePrices.upgrade?(from: starter, to: pro)
    refute RecordingStudioStripe::ComparePrices.new(from: pro, to: starter).upgrade?
    assert RecordingStudioStripe::ComparePrices.new(from: pro, to: starter).downgrade?
  end

  def test_same_product_month_to_year_is_an_upgrade
    monthly = PriceStub.new(unit_amount: 2900, interval: "month", metadata: {}, product_id: "pro")
    annual = PriceStub.new(unit_amount: 29_000, interval: "year", metadata: {}, product_id: "pro")

    assert RecordingStudioStripe::ComparePrices.upgrade?(from: monthly, to: annual)
    assert RecordingStudioStripe::ComparePrices.new(from: annual, to: monthly).downgrade?
  end

  def test_explicit_rank_metadata_wins
    cheap_pro = PriceStub.new(unit_amount: 100, interval: "month", metadata: { "rank" => "20" }, product_id: "pro")
    expensive_starter = PriceStub.new(unit_amount: 9_000, interval: "month", metadata: { "rank" => "10" },
                                      product_id: "starter")

    assert RecordingStudioStripe::ComparePrices.upgrade?(from: expensive_starter, to: cheap_pro)
  end

  def test_same_product_week_to_month_is_an_upgrade
    weekly = PriceStub.new(unit_amount: 900, interval: "week", metadata: {}, product_id: "pro")
    monthly = PriceStub.new(unit_amount: 2900, interval: "month", metadata: {}, product_id: "pro")

    assert RecordingStudioStripe::ComparePrices.upgrade?(from: weekly, to: monthly)
    assert RecordingStudioStripe::ComparePrices.new(from: monthly, to: weekly).downgrade?
    refute RecordingStudioStripe::ComparePrices.new(from: weekly, to: weekly).upgrade?
    refute RecordingStudioStripe::ComparePrices.new(from: weekly, to: weekly).downgrade?
  end

  def test_same_product_week_to_year_is_an_upgrade
    weekly = PriceStub.new(unit_amount: 900, interval: "week", metadata: {}, product_id: "pro")
    annual = PriceStub.new(unit_amount: 29_000, interval: "year", metadata: {}, product_id: "pro")

    assert RecordingStudioStripe::ComparePrices.upgrade?(from: weekly, to: annual)
    assert RecordingStudioStripe::ComparePrices.new(from: annual, to: weekly).downgrade?
  end

  def test_weekly_amount_compares_as_a_monthly_equivalent
    weekly = PriceStub.new(unit_amount: 900, interval: "week", metadata: {}, product_id: "starter")
    monthly = PriceStub.new(unit_amount: 2900, interval: "month", metadata: {}, product_id: "pro")

    assert RecordingStudioStripe::ComparePrices.new(from: weekly, to: monthly).downgrade?
    refute RecordingStudioStripe::ComparePrices.upgrade?(from: weekly, to: monthly)
  end

  def test_a_small_weekly_price_upgrades_to_a_higher_monthly_plan
    weekly = PriceStub.new(unit_amount: 200, interval: "week", metadata: {}, product_id: "starter")
    monthly = PriceStub.new(unit_amount: 2900, interval: "month", metadata: {}, product_id: "pro")

    assert RecordingStudioStripe::ComparePrices.upgrade?(from: weekly, to: monthly)
  end

  def test_rank_still_wins_over_a_weekly_equivalent
    weekly = PriceStub.new(unit_amount: 900, interval: "week", metadata: { "rank" => "20" }, product_id: "pro")
    monthly = PriceStub.new(unit_amount: 2900, interval: "month", metadata: { "rank" => "10" }, product_id: "starter")

    assert RecordingStudioStripe::ComparePrices.upgrade?(from: monthly, to: weekly)
  end
end
