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

  def test_offered_intervals_follow_prices_and_a_host_limit
    product = Struct.new(:priced) do
      def price_for(interval)
        priced[interval.to_s]
      end
    end.new({ "month" => :month, "year" => :year })

    assert_equal %w[month year], RecordingStudioStripe::PlanIntervals.offered([product])
    assert_equal %w[month year], RecordingStudioStripe::PlanIntervals.offered([product], intervals: [])
    assert_equal %w[month], RecordingStudioStripe::PlanIntervals.offered([product], intervals: %w[month week])
    assert_equal "year", RecordingStudioStripe::PlanIntervals.choose([product], "week", intervals: %w[year])
    assert_equal "month", RecordingStudioStripe::PlanIntervals.choose([product], "week")
    assert_equal "week", RecordingStudioStripe::PlanIntervals.choose([product], "month", intervals: %w[week])
  end

  def test_week_is_an_interval_and_day_falls_back_to_month
    assert_equal "week", RecordingStudioStripe::PlanIntervals.from({ interval: "week" }).for("studio")
    assert_equal "month", RecordingStudioStripe::PlanIntervals.from({ interval: "day" }).for("studio")
  end

  def test_hrefs_include_a_weekly_link
    RecordingStudioStripe.configuration.subscription_types = {}
    hrefs = RecordingStudioStripe::PlanIntervals.from({ interval: "month" }).hrefs_for("plan") { |query| query }

    assert_equal "month", hrefs[:interval]
    assert_equal({ interval: "week" }, hrefs[:weekly_href])
    assert_equal({ interval: "month" }, hrefs[:monthly_href])
    assert_equal({ interval: "year" }, hrefs[:yearly_href])
  end

  def test_nested_week_query_keeps_the_other_group_monthly
    RecordingStudioStripe.configuration.subscription_types = {
      "studio" => { "label" => "Studio" },
      "inbox" => { "label" => "Inbox" }
    }
    intervals = RecordingStudioStripe::PlanIntervals.from({ interval: { "inbox" => "year" } })

    assert_equal({ interval: { "studio" => "week", "inbox" => "year" } }, intervals.query("studio", "week"))
    assert_equal "month", intervals.for("studio")
    assert_equal "year", intervals.for("inbox")
  end

  def test_single_type_stays_a_plain_interval_param
    RecordingStudioStripe.configuration.subscription_types = {}
    intervals = RecordingStudioStripe::PlanIntervals.from({ interval: "month" })

    assert_equal({ interval: "year" }, intervals.query("plan", "year"))
  end
end
