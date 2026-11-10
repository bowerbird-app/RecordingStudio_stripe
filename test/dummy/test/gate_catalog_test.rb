# frozen_string_literal: true

require "test_helper"

class GateCatalogTest < ActiveSupport::TestCase
  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @previous_limits = RecordingStudioStripe.configuration.limits
    @previous_usages = RecordingStudioStripe.configuration.limit_usages.dup
  end

  teardown do
    RecordingStudioStripe.configuration.limits = @previous_limits
    RecordingStudioStripe.configuration.limit_usages.replace(@previous_usages)
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
    assert_nil image.aggregation_label

    kits = by_name.fetch("press_kits")
    assert_equal "Limit", kits.kind
    assert_equal "count", kits.aggregation_label
    assert_includes kits.plans, "Starter"

    tokens = by_name.fetch("ai_tokens")
    assert_equal "Meter", tokens.kind
    assert_includes tokens.plans, "Starter"
    assert_includes tokens.plans, "AI token packs"
  end

  test "sync removes undeclared meters and paywalls and their dependents" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter")
    meter = RecordingStudioStripe::Meter.create!(name: "seats", label: "Seats")
    RecordingStudioStripe::Paywall.create!(name: "share_link", label: "Share a link")
    starter.assign_paywalls(starter.paywalls.map(&:name) + %w[share_link])
    starter.assign_plan_card(
      starter.plan_card_settings.merge(
        "hide" => Array(starter.plan_card_settings["hide"]) + %w[meter:seats paywall:share_link],
        "order" => Array(starter.plan_card_settings["order"]) + %w[meter:seats]
      )
    )
    starter.save!

    price = starter.monthly_price
    price.update!(metadata: price.metadata.merge("included_seats" => "3", "meter" => "seats", "allowance" => "9"))

    usage = RecordingStudioStripe::UsageEntry.create!(
      root_recording_id: SecureRandom.uuid,
      meter: meter,
      quantity: 1,
      recorded_at: Time.current
    )
    pack = RecordingStudioStripe::AllowancePurchase.create!(
      root_recording_id: SecureRandom.uuid,
      meter: meter,
      quantity: 5,
      purchased_at: Time.current
    )

    RecordingStudioStripe::Meter.sync_from_config!
    RecordingStudioStripe::Paywall.sync_from_config!

    refute RecordingStudioStripe::Meter.exists?(name: "seats")
    refute RecordingStudioStripe::Paywall.exists?(name: "share_link")
    refute RecordingStudioStripe::UsageEntry.exists?(id: usage.id)
    refute RecordingStudioStripe::AllowancePurchase.exists?(id: pack.id)
    refute starter.reload.paywalls.exists?(name: "share_link")
    refute_includes Array(starter.plan_card_settings["hide"]), "meter:seats"
    refute_includes Array(starter.plan_card_settings["hide"]), "paywall:share_link"
    refute_includes Array(starter.plan_card_settings["order"]), "meter:seats"
    metadata = starter.monthly_price.reload.metadata
    refute metadata.key?("included_seats")
    refute_equal "seats", metadata["meter"]
    refute metadata.key?("allowance")
    assert_nil RecordingStudioStripe::Paywall.named("share_link")
    refute RecordingStudioStripe::GateCatalog.rows.any? { |row| row.name == "seats" }
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
    assert_equal "quantity · No usage reader", storage.aggregation_label
  end
end
