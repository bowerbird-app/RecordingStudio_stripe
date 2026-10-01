# frozen_string_literal: true

require "test_helper"

class LimitUsageTest < Minitest::Test
  def setup
    @previous_limits = RecordingStudioStripe.configuration.limits
    @previous_types = RecordingStudioStripe.configuration.subscription_types
    @previous_usages = RecordingStudioStripe.configuration.limit_usages.dup
    RecordingStudioStripe.configuration.subscription_types = {
      "studio" => { "label" => "Studio" }
    }
  end

  def teardown
    RecordingStudioStripe.configuration.limits = @previous_limits
    RecordingStudioStripe.configuration.subscription_types = @previous_types
    RecordingStudioStripe.configuration.limit_usages.replace(@previous_usages)
  end

  def test_omitted_aggregation_defaults_to_count
    RecordingStudioStripe.configuration.limits = {
      "press_kits" => { "label" => "Press kits", "recordable_type" => "PressKit" }
    }

    definition = RecordingStudioStripe::Limits.fetch(:press_kits)

    assert_equal "count", definition.aggregation
    assert_predicate definition, :count?
  end

  def test_quantity_limit_does_not_need_a_recordable_type
    configure_quantity

    definition = RecordingStudioStripe::Limits.fetch(:storage_bytes)

    assert_equal "quantity", definition.aggregation
    assert_predicate definition, :quantity?
    assert_equal "", definition.recordable_type
    assert_equal ["storage_bytes"], RecordingStudioStripe::Limits.keys
    refute RecordingStudioStripe::Limits.covers_type?("PressKit")
    assert_empty RecordingStudioStripe::Limits.for_recordable_type("PressKit")
    assert_equal "studio", definition.subscription_type
  end

  def test_quantity_limit_with_a_recordable_type_is_not_a_count_gate
    RecordingStudioStripe.configuration.limits = {
      "storage_bytes" => {
        "label" => "Storage",
        "aggregation" => "quantity",
        "recordable_type" => "PressKit",
        "subscription_type" => "studio"
      }
    }

    definition = RecordingStudioStripe::Limits.fetch(:storage_bytes)

    assert_equal "PressKit", definition.recordable_type
    refute definition.covers_type?("PressKit")
    refute RecordingStudioStripe::Limits.covers_type?("PressKit")
  end

  def test_symbol_aggregation_is_accepted
    RecordingStudioStripe.configuration.limits = {
      storage_bytes: { label: "Storage", aggregation: :quantity, subscription_type: "studio" }
    }

    assert_equal "quantity", RecordingStudioStripe::Limits.fetch(:storage_bytes).aggregation
  end

  def test_blank_aggregation_stays_a_count
    RecordingStudioStripe.configuration.limits = {
      "press_kits" => {
        "label" => "Press kits",
        "recordable_type" => "PressKit",
        "aggregation" => ""
      }
    }

    assert_equal "count", RecordingStudioStripe::Limits.fetch(:press_kits).aggregation
  end

  def test_unknown_aggregation_raises
    RecordingStudioStripe.configuration.limits = {
      "storage_bytes" => { "label" => "Storage", "aggregation" => "meter" }
    }

    error = assert_raises(ArgumentError) { RecordingStudioStripe::Limits.keys }

    assert_match(/Unsupported aggregation "meter"/, error.message)
    assert_match(/storage_bytes/, error.message)
    assert_match(/count/, error.message)
    assert_match(/quantity/, error.message)
  end

  def test_register_limit_usage_stores_a_provider_on_configuration
    root = Struct.new(:id).new("root-1")
    RecordingStudioStripe.register_limit_usage(:storage_bytes) { |recording| recording }

    assert_equal root, RecordingStudioStripe.configuration.limit_usage_for(:storage_bytes).call(root)
    assert_equal ["storage_bytes"], RecordingStudioStripe.configuration.to_h.fetch(:limit_usages)
  end

  def test_register_limit_usage_replaces_the_previous_provider
    RecordingStudioStripe.register_limit_usage(:storage_bytes) { 1 }
    RecordingStudioStripe.register_limit_usage("storage_bytes") { 2 }

    assert_equal 2, RecordingStudioStripe.configuration.limit_usage_for(:storage_bytes).call
  end

  def test_register_limit_usage_needs_a_block_and_a_name
    assert_raises(ArgumentError) { RecordingStudioStripe.register_limit_usage(:storage_bytes) }
    error = assert_raises(ArgumentError) { RecordingStudioStripe.register_limit_usage(" ") { 1 } }

    assert_match(/must not be blank/, error.message)
  end

  def test_configuration_registry_is_not_the_singleton
    configuration = RecordingStudioStripe::Configuration.new
    configuration.register_limit_usage(:storage_bytes) { 4 }

    assert_equal 4, configuration.limit_usage_for("storage_bytes").call
    assert_nil RecordingStudioStripe.configuration.limit_usage_for(:storage_bytes)
  end

  def test_quantity_used_calls_the_provider_with_the_root
    configure_quantity
    root = Struct.new(:id).new("root-1")
    seen = nil
    RecordingStudioStripe.register_limit_usage(:storage_bytes) do |recording|
      seen = recording
      12
    end

    handle = handle_for(root)

    assert_equal 12, handle.used
    assert_equal root, seen
    assert_predicate handle, :quantity?
    assert_equal "quantity", handle.aggregation
  end

  def test_zero_usage_is_accepted
    configure_quantity
    RecordingStudioStripe.register_limit_usage(:storage_bytes) { 0 }

    assert_equal 0, handle_for(Struct.new(:id).new("root-1")).used
  end

  def test_negative_or_non_integer_usage_is_rejected
    configure_quantity
    root = Struct.new(:id).new("root-1")

    [-1, 1.5, "10", nil].each do |usage|
      RecordingStudioStripe.register_limit_usage(:storage_bytes) { usage }
      error = assert_raises(ArgumentError) { handle_for(root).used }

      assert_match(/storage_bytes/, error.message)
      assert_match(/non-negative integer/, error.message)
    end
  end

  def test_missing_usage_provider_raises
    configure_quantity
    error = assert_raises(ArgumentError) { handle_for(Struct.new(:id).new("root-1")).used }

    assert_match(/No usage provider registered for limit storage_bytes/, error.message)
    assert_match(/register_limit_usage\(:storage_bytes\)/, error.message)
  end

  def test_blank_root_reports_zero_usage_without_a_provider
    configure_quantity

    assert_equal 0, handle_for(nil).used
  end

  def test_enforce_requires_a_root_and_rejects_a_block
    configure_quantity
    handle = handle_for(nil)
    missing_root = assert_raises(ArgumentError) { handle.enforce!(1) }
    blocked = assert_raises(ArgumentError) { handle.enforce!(1) { :nope } }

    assert_match(/root recording is required/, missing_root.message)
    assert_match(/with_capacity!/, blocked.message)
  end

  def test_invalid_quantity_does_not_call_the_provider
    configure_quantity
    called = false
    RecordingStudioStripe.register_limit_usage(:storage_bytes) do
      called = true
      0
    end
    handle = handle_for(Struct.new(:id).new("root-1"))

    [0, -3, 1.2, "12", nil].each do |quantity|
      error = assert_raises(ArgumentError) { handle.enforce!(quantity) }
      assert_match(/positive integer/, error.message)
    end
    refute called
  end

  def test_with_capacity_needs_a_block
    configure_quantity
    handle = handle_for(Struct.new(:id).new("root-1"))
    error = assert_raises(ArgumentError) { handle.with_capacity!(1) }

    assert_match(/needs a block/, error.message)
  end

  def test_available_rejects_a_quantity_that_is_not_a_positive_integer
    configure_quantity
    assert_rejected_quantities handle_for(nil)
  end

  def test_available_rejects_a_count_that_is_not_a_positive_integer
    configure_count
    assert_rejected_quantities count_handle
  end

  def test_available_default_is_one_and_accepts_a_positive_integer
    configure_quantity
    quantity = handle_for(nil)
    configure_count
    count = count_handle

    [quantity, count].each do |handle|
      assert_equal false, handle.available?
      assert_equal false, handle.available?(1)
      assert_equal false, handle.available?(500_000)
    end
  end

  private

  def configure_quantity
    RecordingStudioStripe.configuration.limits = {
      "storage_bytes" => {
        "label" => "Storage",
        "aggregation" => "quantity",
        "subscription_type" => "studio"
      }
    }
  end

  def configure_count
    RecordingStudioStripe.configuration.limits = {
      "press_kits" => { "label" => "Press kits", "recordable_type" => "PressKit" }
    }
  end

  def handle_for(root)
    RecordingStudioStripe::LimitHandle.new(root_recording: root, name: :storage_bytes)
  end

  def count_handle
    RecordingStudioStripe::LimitHandle.new(root_recording: nil, name: :press_kits)
  end

  def assert_rejected_quantities(handle)
    [0, -1, 1.5, "100", nil].each do |quantity|
      error = assert_raises(ArgumentError) { handle.available?(quantity) }

      assert_match(/positive integer/, error.message)
    end
  end
end
