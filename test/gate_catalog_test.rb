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
      missing_usage: false
    )
    used = RecordingStudioStripe::GateCatalog::Row.new(
      kind: "Paywall",
      name: "generate_image",
      label: "Generate an image",
      aggregation: nil,
      plan_names: %w[Team Pro Team],
      missing_usage: false
    )

    assert_equal "No plan", empty.plans
    assert_equal "Pro, Team", used.plans
    assert_nil empty.aggregation_label
  end

  def test_aggregation_names_a_quantity_limit_without_a_usage_reader
    unread = RecordingStudioStripe::GateCatalog::Row.new(
      kind: "Limit",
      name: "storage_bytes",
      label: "Storage",
      aggregation: "quantity",
      plan_names: %w[Pro],
      missing_usage: true
    )
    ok = RecordingStudioStripe::GateCatalog::Row.new(
      kind: "Limit",
      name: "press_kits",
      label: "Press kits",
      aggregation: "count",
      plan_names: %w[Starter],
      missing_usage: false
    )

    assert_equal "quantity · No usage reader", unread.aggregation_label
    assert_equal "count", ok.aggregation_label
  end
end
