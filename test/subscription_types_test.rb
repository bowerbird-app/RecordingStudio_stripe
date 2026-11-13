# frozen_string_literal: true

require "test_helper"

class SubscriptionTypesTest < Minitest::Test
  def setup
    @previous = RecordingStudioStripe.configuration.subscription_types
  end

  def teardown
    RecordingStudioStripe.configuration.subscription_types = @previous
  end

  def test_empty_config_is_one_implied_plan_group
    RecordingStudioStripe.configuration.subscription_types = {}

    refute RecordingStudioStripe::SubscriptionTypes.configured?
    assert_equal ["plan"], RecordingStudioStripe::SubscriptionTypes.keys
    assert_equal "Plan", RecordingStudioStripe::SubscriptionTypes.label("plan")
    assert_equal "plan", RecordingStudioStripe::SubscriptionTypes.normalize(nil)
    assert_equal :at_period_end, RecordingStudioStripe::SubscriptionTypes.downgrade_timing("plan")
  end

  def test_configured_types_are_the_registry
    RecordingStudioStripe.configuration.subscription_types = {
      press_kits: { label: "Press kits" },
      "media_monitoring" => { "label" => "Media monitoring" }
    }

    assert RecordingStudioStripe::SubscriptionTypes.configured?
    assert_equal %w[press_kits media_monitoring], RecordingStudioStripe::SubscriptionTypes.keys
    assert_equal "Press kits", RecordingStudioStripe::SubscriptionTypes.label(:press_kits)
    assert_equal [["Press kits", "press_kits"], ["Media monitoring", "media_monitoring"]],
                 RecordingStudioStripe::SubscriptionTypes.select_options
    assert_equal :at_period_end, RecordingStudioStripe::SubscriptionTypes.downgrade_timing("press_kits")
  end

  def test_downgrade_timing_reads_immediately
    RecordingStudioStripe.configuration.subscription_types = {
      "studio" => { "label" => "Studio", "downgrade_timing" => :immediately }
    }

    assert_equal :immediately, RecordingStudioStripe::SubscriptionTypes.downgrade_timing(:studio)
  end

  def test_unknown_downgrade_timing_is_rejected_when_assigned
    error = assert_raises(ArgumentError) do
      RecordingStudioStripe.configuration.subscription_types = {
        "studio" => { "downgrade_timing" => "now" }
      }
    end

    assert_match(/downgrade_timing/, error.message)
    assert_equal @previous, RecordingStudioStripe.configuration.subscription_types
  end
end
