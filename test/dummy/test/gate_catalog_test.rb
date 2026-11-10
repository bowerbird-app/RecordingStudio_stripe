# frozen_string_literal: true

require "test_helper"

class GateCatalogTest < ActiveSupport::TestCase
  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @previous_limits = RecordingStudioStripe.configuration.limits
    @previous_usages = RecordingStudioStripe.configuration.limit_usages.dup
    @previous_meters = RecordingStudioStripe.configuration.meters
    @previous_paywalls = RecordingStudioStripe.configuration.paywalls
  end

  teardown do
    RecordingStudioStripe.configuration.limits = @previous_limits
    RecordingStudioStripe.configuration.limit_usages.replace(@previous_usages)
    RecordingStudioStripe.configuration.meters = @previous_meters
    RecordingStudioStripe.configuration.paywalls = @previous_paywalls
  end

  test "lists declared paywalls limits and meters with the products that use them" do
    rows = RecordingStudioStripe::GateCatalog.rows
    by_name = rows.index_by(&:name)

    image = by_name.fetch("generate_image")
    assert_equal "Paywall", image.kind
    assert_equal "Generate an image", image.label
    assert_includes image.plans, "Pro"
    assert_includes image.plans, "Team"
    refute_includes image.plans, "Starter"
    assert_nil image.note

    kits = by_name.fetch("press_kits")
    assert_equal "Limit", kits.kind
    assert_equal "count", kits.aggregation_label
    assert_includes kits.plans, "Starter"
    assert_nil kits.note

    tokens = by_name.fetch("ai_tokens")
    assert_equal "Meter", tokens.kind
    assert_includes tokens.plans, "Starter"
    assert_includes tokens.plans, "AI token packs"
    assert_nil tokens.note
  end

  test "keeps database-only meters and paywalls and flags them" do
    RecordingStudioStripe::Meter.create!(name: "seats", label: "Seats")
    RecordingStudioStripe::Paywall.create!(name: "share_link", label: "Share a link")
    RecordingStudioStripe::Meter.sync_from_config!
    RecordingStudioStripe::Paywall.sync_from_config!

    assert RecordingStudioStripe::Meter.exists?(name: "seats")
    assert RecordingStudioStripe::Paywall.exists?(name: "share_link")

    rows = RecordingStudioStripe::GateCatalog.rows
    seats = rows.find { |row| row.name == "seats" }
    share = rows.find { |row| row.name == "share_link" }

    assert_equal "Meter", seats.kind
    assert_equal "Not in config", seats.note
    assert_equal "No plan", seats.plans
    assert_equal "Paywall", share.kind
    assert_equal "Not in config", share.note
  end

  test "flags quantity limits that have no usage reader" do
    limits = RecordingStudioStripe.configuration.limits.stringify_keys
    limits["storage_bytes"] = {
      "label" => "Storage",
      "aggregation" => "quantity",
      "subscription_type" => "studio"
    }
    RecordingStudioStripe.configuration.limits = limits
    RecordingStudioStripe.configuration.limit_usages.delete("storage_bytes")

    storage = RecordingStudioStripe::GateCatalog.rows.find { |row| row.name == "storage_bytes" }

    assert_equal "Limit", storage.kind
    assert_equal "quantity", storage.aggregation_label
    assert_equal "No usage reader", storage.note
  end
end
