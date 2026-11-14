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

  def test_per_item_limit_needs_no_recordable_type
    configure_per_item

    definition = RecordingStudioStripe::Limits.fetch(:max_file_bytes)

    assert_equal "per_item", definition.aggregation
    assert_predicate definition, :per_item?
    refute_predicate definition, :count?
    assert_equal "", definition.recordable_type
    assert_equal "bytes", definition.unit
    assert_equal 10 * 1024 * 1024, definition.no_plan_limit
    refute definition.covers_type?("PressKit")
    refute RecordingStudioStripe::Limits.covers_type?("Attachment")
    assert_empty RecordingStudioStripe::Limits.for_recordable_type("Attachment")
    assert_equal "Up to 50 MB per file", definition.card_text(50 * 1024 * 1024)
    assert_equal "10 MB", definition.display_quantity(definition.no_plan_limit)
  end

  def test_per_item_without_a_unit_is_a_plain_number
    RecordingStudioStripe.configuration.limits = {
      "max_pages" => { "label" => "Pages", "aggregation" => "per_item" }
    }

    definition = RecordingStudioStripe::Limits.fetch(:max_pages)

    assert_nil definition.unit
    assert_nil definition.no_plan_limit
    assert_equal "Up to 12", definition.card_text(12)
    refute_includes definition.card_text(12), " of "
  end

  def test_per_item_default_line_is_up_to_the_formatted_quantity
    RecordingStudioStripe.configuration.limits = {
      "max_file_bytes" => {
        "label" => "Max file size",
        "aggregation" => "per_item",
        "unit" => "bytes"
      }
    }

    text = RecordingStudioStripe::Limits.fetch(:max_file_bytes).card_text(2 * 1024 * 1024 * 1024)

    assert_equal "Up to 2 GB", text
    refute_includes text, " of "
  end

  def test_no_plan_limit_is_an_optional_positive_integer_on_every_kind
    {
      "press_kits" => { "label" => "Press kits", "recordable_type" => "PressKit", "no_plan_limit" => 2 },
      "storage_bytes" => { "label" => "Storage", "aggregation" => "quantity", "no_plan_limit" => 1024 * 1024 * 1024 },
      "max_file_bytes" => { "aggregation" => "per_item", "no_plan_limit" => 10 * 1024 * 1024 }
    }.each do |name, attrs|
      RecordingStudioStripe.configuration.limits = { name => attrs }
      assert_equal attrs["no_plan_limit"], RecordingStudioStripe::Limits.fetch(name).no_plan_limit
    end

    %w[count quantity per_item].each do |aggregation|
      [0, -1, 1.5, "10", true].each do |value|
        attrs = { "aggregation" => aggregation, "no_plan_limit" => value }
        attrs["recordable_type"] = "PressKit" if aggregation == "count"
        RecordingStudioStripe.configuration.limits = { "rooms" => attrs }
        bad = assert_raises(ArgumentError) { RecordingStudioStripe::Limits.fetch(:rooms) }
        assert_match(/no_plan_limit for limit rooms must be a positive integer or nil/, bad.message)
      end
    end

    RecordingStudioStripe.configuration.limits = {
      "max_file_bytes" => { "aggregation" => "per_item", "no_plan_limit" => nil }
    }
    assert_nil RecordingStudioStripe::Limits.fetch(:max_file_bytes).no_plan_limit
  end

  def test_bytes_display_on_a_quantity_limit
    RecordingStudioStripe.configuration.limits = {
      "storage_bytes" => {
        "label" => "Storage",
        "aggregation" => "quantity",
        "unit" => "bytes",
        "plan_line" => "%{quantity} storage" # rubocop:disable Style/FormatStringToken
      }
    }
    definition = RecordingStudioStripe::Limits.fetch(:storage_bytes)

    bytes = 5 * 1024 * 1024 * 1024
    assert_equal "5 GB", definition.display_quantity(bytes)
    assert_equal "5 GB storage", definition.card_text(bytes)
    shown = definition.shown_amount(bytes)
    assert_equal "5 GB", shown.to_s
    assert_equal bytes, shown.to_i
    assert_operator shown, :>, 0
  end

  def test_limit_action_is_upgrade_purchase_or_omitted
    RecordingStudioStripe.configuration.limits = {
      "storage_bytes" => {
        "label" => "Storage",
        "aggregation" => "quantity",
        "action" => "upgrade"
      }
    }
    definition = RecordingStudioStripe::Limits.fetch(:storage_bytes)
    assert_equal "upgrade", definition.action
    assert_equal "Upgrade", definition.action_label
    assert_nil definition.action_url
    assert_nil definition.action_method

    RecordingStudioStripe.configuration.limits = {
      "credits" => {
        "label" => "Credits",
        "aggregation" => "quantity",
        "action" => "purchase",
        "action_label" => "Buy credits",
        "action_url" => "/credits",
        "action_method" => "post"
      }
    }
    credits = RecordingStudioStripe::Limits.fetch(:credits)
    assert_equal "purchase", credits.action
    assert_equal "Buy credits", credits.action_label
    assert_equal "/credits", credits.action_url
    assert_equal "post", credits.action_method

    callable = -> { "/addons" }
    RecordingStudioStripe.configuration.limits = {
      "storage_bytes" => {
        "aggregation" => "quantity",
        "action" => "purchase",
        "action_url" => callable
      }
    }
    assert_equal callable, RecordingStudioStripe::Limits.fetch(:storage_bytes).action_url
    assert_equal "Buy more", RecordingStudioStripe::Limits.fetch(:storage_bytes).action_label
    assert_equal "count", RecordingStudioStripe::Limits.fetch(:storage_bytes).display

    ["widgets", 1, true].each do |value|
      RecordingStudioStripe.configuration.limits = {
        "storage_bytes" => { "aggregation" => "quantity", "action" => value }
      }
      error = assert_raises(ArgumentError) { RecordingStudioStripe::Limits.fetch(:storage_bytes) }
      assert_match(/action for limit storage_bytes must be "upgrade", "purchase", or omitted/, error.message)
    end

    RecordingStudioStripe.configuration.limits = {
      "storage_bytes" => { "aggregation" => "quantity", "action" => "purchase" }
    }
    missing = assert_raises(ArgumentError) { RecordingStudioStripe::Limits.fetch(:storage_bytes) }
    assert_match(/action_url for limit storage_bytes is required when action is purchase/, missing.message)
  end

  def test_limit_display_is_count_or_percent
    RecordingStudioStripe.configuration.limits = {
      "storage_bytes" => { "aggregation" => "quantity", "display" => "percent" }
    }
    assert_equal "percent", RecordingStudioStripe::Limits.fetch(:storage_bytes).display

    RecordingStudioStripe.configuration.limits = {
      "storage_bytes" => { "aggregation" => "quantity" }
    }
    assert_equal "count", RecordingStudioStripe::Limits.fetch(:storage_bytes).display

    RecordingStudioStripe.configuration.limits = {
      "storage_bytes" => { "aggregation" => "quantity", "display" => "ratio" }
    }
    error = assert_raises(ArgumentError) { RecordingStudioStripe::Limits.fetch(:storage_bytes) }
    assert_match(/display for limit storage_bytes must be "count" or "percent"/, error.message)

    previous_meters = RecordingStudioStripe.configuration.meters
    RecordingStudioStripe.configuration.meters = { "ai_tokens" => { "label" => "AI tokens", "display" => "percent" } }
    meter = Struct.new(:name).new("ai_tokens")
    handle = RecordingStudioStripe::MeterHandle.new(root_recording: nil, meter: meter)
    assert_equal "percent", handle.usage_display
    RecordingStudioStripe.configuration.meters = { "ai_tokens" => { "label" => "AI tokens", "display" => "shares" } }
    bad = assert_raises(ArgumentError) { handle.usage_display }
    assert_match(/display for meter ai_tokens must be "count" or "percent"/, bad.message)
  ensure
    RecordingStudioStripe.configuration.meters = previous_meters if previous_meters
  end

  def test_unknown_unit_raises
    RecordingStudioStripe.configuration.limits = {
      "max_file_bytes" => { "aggregation" => "per_item", "unit" => "widgets" }
    }

    error = assert_raises(ArgumentError) { RecordingStudioStripe::Limits.fetch(:max_file_bytes) }

    assert_match(/Unsupported unit "widgets"/, error.message)
    assert_match(/bytes/, error.message)
  end

  def test_per_item_ceiling_without_a_plan_uses_no_plan_limit
    configure_per_item
    handle = per_item_handle

    assert_equal 10 * 1024 * 1024, handle.ceiling
    assert handle.allows?(10 * 1024 * 1024)
    refute handle.allows?((10 * 1024 * 1024) + 1)
    handle.enforce_item!(1024)
    error = assert_raises(RecordingStudioStripe::PlanLimitReached) { handle.enforce_item!(11 * 1024 * 1024) }

    assert_equal handle, error.handle
    assert_equal "This file is larger than your plan allows. Upgrade for bigger uploads.", error.user_message
    assert_equal error.user_message, error.message
  end

  def test_per_item_without_no_plan_limit_allows_any_positive_amount
    RecordingStudioStripe.configuration.limits = {
      "max_file_bytes" => { "aggregation" => "per_item", "unit" => "bytes" }
    }
    handle = per_item_handle

    assert_nil handle.ceiling
    assert handle.allows?(50 * 1024 * 1024 * 1024)
    handle.enforce_item!(50 * 1024 * 1024 * 1024)
  end

  def test_per_item_aggregate_methods_raise_and_item_methods_reject_other_kinds
    configure_per_item
    handle = per_item_handle
    %i[used remaining over?].each do |method_name|
      error = assert_raises(ArgumentError) { handle.public_send(method_name) }
      assert_match(/Use ceiling or enforce_item!/, error.message)
    end
    error = assert_raises(ArgumentError) { handle.available?(1) }
    assert_match(/Use ceiling or enforce_item!/, error.message)
    error = assert_raises(ArgumentError) { handle.enforce!(1) }
    assert_match(/Use ceiling or enforce_item!/, error.message)
    error = assert_raises(ArgumentError) { handle.with_capacity!(1) { true } }
    assert_match(/Use ceiling or enforce_item!/, error.message)

    [0, -1, 1.5, "100", nil].each do |amount|
      error = assert_raises(ArgumentError) { handle.allows?(amount) }
      assert_match(/positive integer/, error.message)
      error = assert_raises(ArgumentError) { handle.enforce_item!(amount) }
      assert_match(/positive integer/, error.message)
    end

    configure_count
    count = count_handle
    {
      ceiling: -> { count.ceiling },
      allows?: -> { count.allows?(1) },
      enforce_item!: -> { count.enforce_item!(1) }
    }.each_value do |call|
      error = assert_raises(ArgumentError, &call)
      assert_match(/per-item ceiling/, error.message)
      assert_match(/count limit/, error.message)
    end
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

  def configure_per_item
    RecordingStudioStripe.configuration.limits = {
      "max_file_bytes" => {
        "label" => "Max file size",
        "aggregation" => "per_item",
        "unit" => "bytes",
        "plan_line" => "Up to %{quantity} per file", # rubocop:disable Style/FormatStringToken
        "no_plan_limit" => 10 * 1024 * 1024
      }
    }
  end

  def per_item_handle
    RecordingStudioStripe::LimitHandle.new(root_recording: nil, name: :max_file_bytes)
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
