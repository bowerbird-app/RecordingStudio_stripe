# frozen_string_literal: true

require "test_helper"

class PlanIntervalsTest < Minitest::Test
  def setup
    @previous = RecordingStudioStripe.configuration.subscription_types
  end

  def teardown
    RecordingStudioStripe.configuration.subscription_types = @previous
  end

  def test_blank_params_are_monthly
    intervals = RecordingStudioStripe::PlanIntervals.from({})

    assert_equal "month", intervals.for("studio")
    assert_equal({ interval: "month" }, intervals.query("plan", "month"))
  end

  def test_scalar_interval_applies_to_every_group
    RecordingStudioStripe.configuration.subscription_types = {
      "studio" => { "label" => "Studio" },
      "inbox" => { "label" => "Inbox" }
    }
    intervals = RecordingStudioStripe::PlanIntervals.from({ interval: "year" })

    assert_equal "year", intervals.for("studio")
    assert_equal "year", intervals.for("inbox")
  end

  def test_nested_interval_is_per_group
    RecordingStudioStripe.configuration.subscription_types = {
      "studio" => { "label" => "Studio" },
      "inbox" => { "label" => "Inbox" }
    }
    intervals = RecordingStudioStripe::PlanIntervals.from(
      { interval: { "studio" => "year" } }
    )

    assert_equal "year", intervals.for("studio")
    assert_equal "month", intervals.for("inbox")
  end

  def test_query_keeps_the_other_group
    RecordingStudioStripe.configuration.subscription_types = {
      "studio" => { "label" => "Studio" },
      "inbox" => { "label" => "Inbox" }
    }
    intervals = RecordingStudioStripe::PlanIntervals.from(
      { interval: { "studio" => "year" } }
    )

    assert_equal({ interval: { "studio" => "year", "inbox" => "year" } }, intervals.query("inbox", "year"))
    assert_equal({}, intervals.query("studio", "month"))
  end

  def test_single_type_stays_a_plain_interval_param
    RecordingStudioStripe.configuration.subscription_types = {}
    intervals = RecordingStudioStripe::PlanIntervals.from({ interval: "month" })

    assert_equal({ interval: "year" }, intervals.query("plan", "year"))
  end
end
