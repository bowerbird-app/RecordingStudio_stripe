# frozen_string_literal: true

require "test_helper"

class LimitsTest < Minitest::Test
  def setup
    @previous = RecordingStudioStripe.configuration.limits
    @previous_types = RecordingStudioStripe.configuration.subscription_types
  end

  def teardown
    RecordingStudioStripe.configuration.limits = @previous
    RecordingStudioStripe.configuration.subscription_types = @previous_types
  end

  def test_empty_config_is_not_configured
    RecordingStudioStripe.configuration.limits = {}

    refute RecordingStudioStripe::Limits.configured?
    assert_empty RecordingStudioStripe::Limits.keys
    refute RecordingStudioStripe::Limits.covers_type?("PressKit")
  end

  def test_configured_limits_are_the_registry
    RecordingStudioStripe.configuration.subscription_types = {
      "studio" => { "label" => "Studio" }
    }
    RecordingStudioStripe.configuration.limits = {
      press_kits: {
        label: "Press kits",
        recordable_type: "PressKit",
        subscription_type: "studio"
      }
    }

    assert RecordingStudioStripe::Limits.configured?
    assert_equal ["press_kits"], RecordingStudioStripe::Limits.keys
    definition = RecordingStudioStripe::Limits.fetch(:press_kits)
    assert_equal "Press kits", definition.label
    assert_equal "PressKit", definition.recordable_type
    assert_equal "studio", definition.subscription_type
    assert RecordingStudioStripe::Limits.covers_type?("PressKit")
    refute RecordingStudioStripe::Limits.covers_type?("Folder")
  end

  def test_omitted_subscription_type_uses_matching_plan_group
    RecordingStudioStripe.configuration.subscription_types = {
      "press_kits" => { "label" => "Press kits" }
    }
    RecordingStudioStripe.configuration.limits = {
      "press_kits" => { "label" => "Press kits", "recordable_type" => "PressKit" }
    }

    assert_equal "press_kits", RecordingStudioStripe::Limits.fetch(:press_kits).subscription_type
  end

  def test_omitted_subscription_type_falls_back_to_first_group
    RecordingStudioStripe.configuration.subscription_types = {
      "studio" => { "label" => "Studio" },
      "inbox" => { "label" => "Inbox" }
    }
    RecordingStudioStripe.configuration.limits = {
      "press_kits" => { "label" => "Press kits", "recordable_type" => "PressKit" }
    }

    assert_equal "studio", RecordingStudioStripe::Limits.fetch(:press_kits).subscription_type
  end

  def test_unknown_limit_raises
    RecordingStudioStripe.configuration.limits = {}

    error = assert_raises(ArgumentError) { RecordingStudioStripe::Limits.fetch(:press_kits) }
    assert_match(/Unknown limit press_kits/, error.message)
  end

  def test_entries_without_recordable_type_are_skipped
    RecordingStudioStripe.configuration.limits = {
      "press_kits" => { "label" => "Press kits" }
    }

    assert_empty RecordingStudioStripe::Limits.keys
  end

  def test_advisory_lock_is_a_noop_on_non_postgres
    connection = Object.new
    def connection.adapter_name
      "SQLite"
    end

    def connection.execute(*)
      raise "advisory lock should not run"
    end

    RecordingStudioStripe::AdvisoryLock.hold(connection, "demo")
  end
end
