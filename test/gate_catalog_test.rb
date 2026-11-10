# frozen_string_literal: true

require "test_helper"

class GateCatalogTest < Minitest::Test
  def test_plans_join_unique_names_or_no_plan
    empty = RecordingStudioStripe::GateCatalog::Row.new(
      kind: "Paywall",
      name: "export_csv",
      label: "Export CSV",
      aggregation: nil,
      plan_names: [],
      in_config: true,
      missing_usage: false
    )
    used = RecordingStudioStripe::GateCatalog::Row.new(
      kind: "Paywall",
      name: "generate_image",
      label: "Generate an image",
      aggregation: nil,
      plan_names: %w[Team Pro Team],
      in_config: true,
      missing_usage: false
    )

    assert_equal "No plan", empty.plans
    assert_equal "Pro, Team", used.plans
    assert_equal "—", empty.aggregation_label
  end

  def test_note_flags_missing_config_and_quantity_reader
    stray = RecordingStudioStripe::GateCatalog::Row.new(
      kind: "Meter",
      name: "seats",
      label: "Seats",
      aggregation: nil,
      plan_names: [],
      in_config: false,
      missing_usage: false
    )
    unread = RecordingStudioStripe::GateCatalog::Row.new(
      kind: "Limit",
      name: "storage_bytes",
      label: "Storage",
      aggregation: "quantity",
      plan_names: %w[Pro],
      in_config: true,
      missing_usage: true
    )
    ok = RecordingStudioStripe::GateCatalog::Row.new(
      kind: "Limit",
      name: "press_kits",
      label: "Press kits",
      aggregation: "count",
      plan_names: %w[Starter],
      in_config: true,
      missing_usage: false
    )

    assert_equal "Not in config", stray.note
    assert_equal "No usage reader", unread.note
    assert_nil ok.note
    assert_equal "quantity", unread.aggregation_label
  end
end
