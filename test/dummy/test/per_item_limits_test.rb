# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class PerItemLimitsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @previous_limits = RecordingStudioStripe.configuration.limits
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @workspace = Workspace.create!(name: "File Ceiling #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_owner_access!(recording: @root, actor: @user)
    Current.actor = @user
    sign_in @user
    switch_to_root!(@root)
    @starter = RecordingStudioStripe::Product.find_by!(name: "Starter")
    @pro = RecordingStudioStripe::Product.find_by!(name: "Pro")
    @team = RecordingStudioStripe::Product.find_by!(name: "Team")
  end

  teardown do
    RecordingStudioStripe.configuration.limits = @previous_limits
  end

  test "a live plan ceiling allows up to that size and denies the next byte" do
    subscribe!(@starter)

    handle = @workspace.billing.limit(:max_file_bytes)

    assert_equal 50.megabytes, handle.ceiling
    assert handle.allows?(50.megabytes)
    refute handle.allows?(50.megabytes + 1)
    handle.enforce_item!(50.megabytes)
    error = assert_raises(RecordingStudioStripe::PlanLimitReached) do
      handle.enforce_item!(50.megabytes + 1)
    end

    assert_equal "This file is larger than your plan allows. Upgrade for bigger uploads.", error.user_message
  end

  test "a live plan that omits the key has no ceiling" do
    subscribe!(@team)

    handle = @workspace.billing.limit(:max_file_bytes)

    assert_nil @team.metadata["limit_max_file_bytes"]
    assert_nil handle.ceiling
    assert handle.allows?(2.gigabytes)
    handle.enforce_item!(2.gigabytes)
  end

  test "no plan uses no_plan_ceiling and a canceled plan falls back to it" do
    bare = @workspace.billing.limit(:max_file_bytes)

    assert_equal 10.megabytes, bare.ceiling
    assert bare.allows?(10.megabytes)
    refute bare.allows?(10.megabytes + 1)

    subscribe!(@starter)
    subscription = RecordingStudioStripe::Subscription.current_for(
      root_recording_id: @root.id,
      subscription_type: "studio"
    )
    subscription.update!(status: "canceled")
    canceled = @workspace.billing.limit(:max_file_bytes)

    assert_nil canceled.subscription
    assert_equal 10.megabytes, canceled.ceiling
    refute canceled.allows?(10.megabytes + 1)
  end

  test "no plan without no_plan_ceiling has no cap" do
    drop_no_plan_ceiling

    handle = @workspace.billing.limit(:max_file_bytes)

    assert_nil handle.ceiling
    assert handle.allows?(2.gigabytes)
    handle.enforce_item!(2.gigabytes)
  end

  test "past_due keeps the plan ceiling" do
    subscribe!(@pro)
    subscription = RecordingStudioStripe::Subscription.current_for(
      root_recording_id: @root.id,
      subscription_type: "studio"
    )
    subscription.update!(status: "past_due")
    handle = @workspace.billing.limit(:max_file_bytes)

    assert_equal "past_due", handle.subscription.status
    assert_equal 2.gigabytes, handle.ceiling
    assert handle.allows?(2.gigabytes)
    refute handle.allows?(2.gigabytes + 1)
  end

  test "plan cards say up to the file size and gates list the per-item row" do
    starter_lines = RecordingStudioStripe::PlanFeatures.for(@starter, @starter.monthly_price).map(&:text)
    pro_lines = RecordingStudioStripe::PlanFeatures.for(@pro, @pro.monthly_price).map(&:text)
    team_lines = RecordingStudioStripe::PlanFeatures.for(@team, @team.monthly_price).map(&:text)

    assert_includes starter_lines, "Up to 50 MB per file"
    assert_includes pro_lines, "Up to 2 GB per file"
    refute_includes team_lines, "Up to 50 MB per file"
    starter_lines.each { |line| refute_includes line, " of " }

    row = RecordingStudioStripe::GateCatalog.rows.find { |entry| entry.name == "max_file_bytes" }

    assert_equal "Limit", row.kind
    assert_equal "per item", row.aggregation_label
    assert_includes row.plans, "Starter"
    assert_includes row.plans, "Pro"
    assert_includes row.plans, "10 MB with no plan"
    refute_includes row.aggregation_label, "No usage reader"
  end

  test "the count gate and usage page ignore a per-item limit" do
    @starter.assign_limits("max_file_bytes" => 1)
    @starter.save!
    subscribe!(@starter)

    assert_difference -> { PressKit.count }, 1 do
      @root.record(PressKit) { |kit| kit.name = "Still allowed" }
    end
    assert_raises(RecordingStudioStripe::PlanLimitReached) do
      @workspace.billing.limit(:max_file_bytes).enforce_item!(2)
    end

    get recording_studio_stripe.usage_path

    assert_response :success
    assert_includes response.body, "Press kits"
    refute_includes response.body, "Max file size"
    refute_includes response.body, "per file"
  end

  test "a host with no per-item limit is unchanged" do
    press_kits = RecordingStudioStripe.configuration.limits.to_h.deep_stringify_keys.fetch("press_kits")
    RecordingStudioStripe.configuration.limits = { "press_kits" => press_kits }
    subscribe!(@starter)

    lines = RecordingStudioStripe::PlanFeatures.for(@starter, @starter.monthly_price).map(&:text)
    refute lines.any? { |line| line.include?("per file") || line.include?("MB") }
    refute RecordingStudioStripe::GateCatalog.rows.any? { |row| row.name == "max_file_bytes" }
    assert RecordingStudioStripe::Limits.covers_type?("PressKit")
    refute RecordingStudioStripe::Limits.all.any?(&:per_item?)

    assert_difference -> { PressKit.count }, 1 do
      @root.record(PressKit) { |kit| kit.name = "Ordinary kit" }
    end

    get recording_studio_stripe.usage_path

    assert_response :success
    assert_includes response.body, "Press kits"
    assert_includes response.body, "1 of 3"
    refute_includes response.body, "Max file size"
  end

  test "html and json responses for a per-item PlanLimitReached match the other limits" do
    subscribe!(@starter)

    post uploads_path, params: { byte_size: 51.megabytes }

    assert_redirected_to "/plans"
    follow_redirect!
    assert_includes response.body, "This file is larger than your plan allows. Upgrade for bigger uploads."

    post uploads_path, params: { byte_size: 51.megabytes }, as: :json

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "plan_limit_reached", body.fetch("code")
    assert_equal "This file is larger than your plan allows. Upgrade for bigger uploads.", body.fetch("message")

    post uploads_path, params: { byte_size: 50.megabytes }

    assert_redirected_to "/"
  end

  test "admin product form stores the per-item byte integer" do
    admin_root = AdminRoot.find_or_create_by!(name: "Studio Admin")
    admin_recording = RecordingStudio.root_recording_for(admin_root)
    grant_owner_access!(recording: admin_recording, actor: @user)
    switch_to_root!(admin_recording)

    get RecordingStudioStripe.configuration.mount_path + "/admin/products/#{@starter.id}/edit"

    assert_response :success
    assert_select "input[name='limits[max_file_bytes]'][value='#{50.megabytes}']"

    name = "File Plan #{SecureRandom.hex(2)}"
    assert_difference -> { RecordingStudioStripe::Product.count }, 1 do
      post RecordingStudioStripe.configuration.mount_path + "/admin/products", params: {
        name: name,
        kind: "plan",
        subscription_type: "studio",
        description: "Room for a file.",
        limits: { press_kits: 1, max_file_bytes: 2.gigabytes }
      }
    end

    product = RecordingStudioStripe::Product.find_by!(name: name)

    assert_equal 2.gigabytes, product.limit_quantity("max_file_bytes")
    assert_equal 2.gigabytes.to_s, product.metadata["limit_max_file_bytes"]

    get RecordingStudioStripe.configuration.mount_path + "/admin/products/#{product.id}/edit"

    assert_response :success
    assert_select "input[name='limits[max_file_bytes]'][value='#{2.gigabytes}']"
  end

  test "gates screen shows the per-item row and the no-plan ceiling" do
    admin_root = AdminRoot.find_or_create_by!(name: "Studio Admin")
    admin_recording = RecordingStudio.root_recording_for(admin_root)
    grant_owner_access!(recording: admin_recording, actor: @user)
    switch_to_root!(admin_recording)

    get "/admin/screens/gates/table"

    assert_response :success
    assert_includes response.body, "max_file_bytes"
    assert_includes response.body, "per item"
    assert_includes response.body, "10 MB with no plan"
    assert_includes response.body, "Max file size"
  end

  private

  def subscribe!(product)
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: product.monthly_price)
  end

  def drop_no_plan_ceiling
    limits = RecordingStudioStripe.configuration.limits.to_h.deep_stringify_keys
    limits["max_file_bytes"] = limits["max_file_bytes"].except("no_plan_ceiling")
    RecordingStudioStripe.configuration.limits = limits
  end
end
