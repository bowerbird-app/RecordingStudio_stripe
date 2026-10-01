# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class QuantityLimitScreensTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @previous_limits = RecordingStudioStripe.configuration.limits
    @previous_usages = RecordingStudioStripe.configuration.limit_usages.dup
    limits = @previous_limits.to_h.deep_stringify_keys
    limits["storage_bytes"] = {
      "label" => "Storage",
      "aggregation" => "quantity",
      "subscription_type" => "studio"
    }
    RecordingStudioStripe.configuration.limits = limits
    RecordingStudioStripe.register_limit_usage(:storage_bytes) { 3_500_000_000 }
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_owner_access!(recording: @root, actor: @user)
    @starter = RecordingStudioStripe::Product.find_by!(name: "Starter")
    @starter_metadata = @starter.metadata.deep_dup
    @starter.assign_limits("press_kits" => 3, "storage_bytes" => 5_000_000_000)
    @starter.save!
    sign_in @user
  end

  teardown do
    @starter.update!(metadata: @starter_metadata) if @starter&.persisted?
    RecordingStudioStripe.configuration.limits = @previous_limits
    RecordingStudioStripe.configuration.limit_usages.replace(@previous_usages)
  end

  test "usage shows the raw quantity beside the count limit" do
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: @starter.monthly_price)
    switch_to_root!(@root)

    get recording_studio_stripe.usage_path

    assert_response :success
    assert_includes response.body, "Press kits"
    assert_includes response.body, "Storage"
    assert_includes response.body, "3500000000/5000000000"
  end

  test "admin plan forms keep quantity limits as integer fields" do
    @admin_root = AdminRoot.find_or_create_by!(name: "Studio Admin")
    @admin_recording = RecordingStudio.root_recording_for(@admin_root)
    grant_owner_access!(recording: @admin_recording, actor: @user)
    switch_to_root!(@admin_recording)

    get RecordingStudioStripe.configuration.mount_path + "/admin/products/new"

    assert_response :success
    assert_select "input[name='limits[press_kits]']"
    assert_select "input[name='limits[storage_bytes]']"
    assert_includes response.body, "Blank means none. Monthly and yearly share this number."

    assert_difference -> { RecordingStudioStripe::Product.count }, 1 do
      post RecordingStudioStripe.configuration.mount_path + "/admin/products", params: {
        name: "Quantity Plan",
        kind: "plan",
        subscription_type: "studio",
        description: "Room for files.",
        limits: { press_kits: 4, storage_bytes: 5_000_000_000 }
      }
    end

    product = RecordingStudioStripe::Product.find_by!(name: "Quantity Plan")

    assert_equal 4, product.limit_quantity("press_kits")
    assert_equal 5_000_000_000, product.limit_quantity("storage_bytes")
    assert_equal "5000000000", product.metadata["limit_storage_bytes"]
    assert_equal "4", product.metadata["limit_press_kits"]

    get RecordingStudioStripe.configuration.mount_path + "/admin/products/#{product.id}/edit"

    assert_response :success
    assert_select "input[name='limits[storage_bytes]'][value='5000000000']"
  end
end
