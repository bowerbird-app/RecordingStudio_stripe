# frozen_string_literal: true

require "test_helper"

class UsageTariffTest < Minitest::Test
  def setup
    @previous_costs = RecordingStudioStripe.configuration.usage_costs
    RecordingStudioStripe.configuration.usage_costs = {
      "ai.jev" => 1,
      "web.brave" => 5
    }
  end

  def teardown
    RecordingStudioStripe.configuration.usage_costs = @previous_costs
  end

  def test_usage_cost_returns_the_configured_rate
    assert_equal 5, RecordingStudioStripe.usage_cost("web.brave")
    assert_equal 1, RecordingStudioStripe.usage_cost("ai.jev")
  end

  def test_unknown_usage_key_raises
    error = assert_raises(ArgumentError) { RecordingStudioStripe.usage_cost("web.missing") }

    assert_equal 'Unknown usage "web.missing"', error.message
  end

  def test_usage_key_must_be_a_string
    error = assert_raises(ArgumentError) { RecordingStudioStripe.usage_cost(:web_brave) }

    assert_equal "usage key must be a String", error.message
  end

  def test_charge_multiplies_quantity_by_the_rate
    charge = RecordingStudioStripe::UsageTariff.charge(key: "web.brave", quantity: 2)

    assert_equal "web.brave", charge.key
    assert_equal 2, charge.quantity
    assert_equal 5, charge.rate
    assert_equal 10, charge.credits
  end

  def test_charge_defaults_quantity_to_one
    assert_equal 5, RecordingStudioStripe::UsageTariff.charge(key: "web.brave").credits
  end

  def test_quantity_must_be_a_positive_integer
    assert_raises(ArgumentError) { RecordingStudioStripe::UsageTariff.charge(key: "web.brave", quantity: 0) }
    assert_raises(ArgumentError) { RecordingStudioStripe::UsageTariff.charge(key: "web.brave", quantity: -1) }
    assert_raises(ArgumentError) { RecordingStudioStripe::UsageTariff.charge(key: "web.brave", quantity: 2.5) }
    assert_raises(ArgumentError) { RecordingStudioStripe::UsageTariff.charge(key: "web.brave", quantity: "2") }
  end
end
