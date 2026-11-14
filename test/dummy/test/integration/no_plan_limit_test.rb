# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class NoPlanLimitTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @previous_limits = RecordingStudioStripe.configuration.limits
    @previous_usages = RecordingStudioStripe.configuration.limit_usages.dup
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @workspace = Workspace.create!(name: "Base Limit #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_owner_access!(recording: @root, actor: @user)
    Current.actor = @user
    @starter = RecordingStudioStripe::Product.find_by!(name: "Starter")
    @starter_metadata = @starter.metadata.deep_dup
    @usage = 0
    sign_in @user
  end

  teardown do
    @starter.update!(metadata: @starter_metadata) if @starter&.persisted?
    RecordingStudioStripe.configuration.limits = @previous_limits
    RecordingStudioStripe.configuration.limit_usages.replace(@previous_usages)
  end

  test "a quantity base with no plan allows up to the base and blocks beyond" do
    configure_storage!(base: 1.gigabyte)

    storage = @workspace.billing.limit(:storage_bytes)

    assert_nil storage.product
    assert_equal 1.gigabyte, storage.included
    assert storage.available?(1.gigabyte)
    refute storage.available?(1.gigabyte + 1)
    storage.with_capacity!(1.gigabyte) { @usage = 1.gigabyte }
    assert_equal 1.gigabyte, @usage

    error = assert_raises(RecordingStudioStripe::PlanLimitReached) do
      storage.with_capacity!(1) { flunk "wrote past the base" }
    end

    assert_equal 1.gigabyte, @usage
    assert_equal "The cap is 1 GB storage. Upgrade, or free some up.", error.user_message
    refute_includes error.user_message, "this plan"
  end

  test "a live plan overrides the base, including a lower number and zero" do
    configure_storage!(base: 1.gigabyte)
    @starter.assign_limits("storage_bytes" => 5.gigabytes)
    @starter.save!
    subscribe!

    storage = @workspace.billing.limit(:storage_bytes)
    assert_equal 5.gigabytes, storage.included
    assert storage.available?(2.gigabytes)

    @starter.assign_limits("storage_bytes" => 500.megabytes)
    @starter.save!
    lower = @workspace.billing.limit(:storage_bytes)
    assert_equal 500.megabytes, lower.included
    assert lower.available?(500.megabytes)
    refute lower.available?(500.megabytes + 1)

    @starter.update!(metadata: @starter.metadata.merge("limit_storage_bytes" => "0"))
    none = @workspace.billing.limit(:storage_bytes)
    assert_equal 0, none.included
    refute none.available?(1)

    error = assert_raises(RecordingStudioStripe::PlanLimitReached) do
      none.with_capacity!(1) { flunk "wrote on a zero plan" }
    end
    assert_equal "Pick a plan to add storage.", error.user_message

    @starter.assign_limits("storage_bytes" => nil)
    @starter.save!
    blank = @workspace.billing.limit(:storage_bytes)
    assert_equal 0, blank.included
  end

  test "canceling onto a lower base blocks new writes and deletes nothing" do
    configure_storage!(base: 1.gigabyte)
    @usage = 2.gigabytes
    @starter.assign_limits("storage_bytes" => 5.gigabytes)
    @starter.save!
    subscribe!
    assert @workspace.billing.limit(:storage_bytes).available?(1)

    loss = RecordingStudioStripe::PlanLoss.new(
      from_product: @starter,
      to_product: nil,
      subscription_type: "studio"
    )
    assert_includes loss.limits_lowered, { name: "storage_bytes", from: 5.gigabytes, to: 1.gigabyte }

    subscription = RecordingStudioStripe::Subscription.current_for(root_recording_id: @root.id)
    subscription.update!(status: "canceled")
    assert_nil RecordingStudioStripe::Subscription.current_for(root_recording_id: @root.id)

    storage = @workspace.billing.limit(:storage_bytes)
    assert_equal 1.gigabyte, storage.included
    assert_equal 2.gigabytes, storage.used
    assert storage.over?

    error = assert_raises(RecordingStudioStripe::PlanLimitReached) do
      storage.with_capacity!(1) { @usage = 0 }
    end

    assert_equal 2.gigabytes, @usage
    assert_equal 2.gigabytes, @workspace.billing.limit(:storage_bytes).used
    assert_includes error.user_message, "1 GB"

    switch_to_root!(@root)
    get recording_studio_stripe.usage_path

    assert_response :success
    assert_includes response.body, "2 GB of 1 GB"
    assert_includes response.body, "Over the limit"
  end

  test "a count base allows that many recordings and a plan of zero blocks" do
    configure_press_kits!(base: 2)

    2.times { |index| record_press_kit!("Kit #{index}") }
    assert_equal 2, @workspace.billing.limit(:press_kits).used

    error = assert_raises(RecordingStudioStripe::PlanLimitReached) { record_press_kit!("One too many") }
    assert_equal "The cap is 2 press kits. Upgrade, or archive one.", error.user_message
    refute_includes error.user_message, "this plan"
    assert_equal 2, @workspace.billing.limit(:press_kits).used

    @starter.assign_limits("press_kits" => 4)
    @starter.save!
    subscribe!
    record_press_kit!("Plan kit")
    assert_equal 3, @workspace.billing.limit(:press_kits).used

    @starter.assign_limits("press_kits" => 1)
    @starter.save!
    assert_equal 1, @workspace.billing.limit(:press_kits).included
    assert_raises(RecordingStudioStripe::PlanLimitReached) { record_press_kit!("Under the plan") }
    assert_equal 3, @workspace.billing.limit(:press_kits).used

    @starter.update!(metadata: @starter.metadata.merge("limit_press_kits" => "0"))
    assert_equal 0, @workspace.billing.limit(:press_kits).included
    assert_raises(RecordingStudioStripe::PlanLimitReached) { record_press_kit!("Zero plan") }
    assert_equal 3, @workspace.billing.limit(:press_kits).used

    loss = RecordingStudioStripe::PlanLoss.new(
      from_product: @starter,
      to_product: nil,
      subscription_type: "studio"
    )
    refute_includes loss.limits_lowered.map { |row| row[:name] }, "press_kits"

    @starter.assign_limits("press_kits" => 4)
    @starter.save!
    listed = RecordingStudioStripe::PlanLoss.new(
      from_product: @starter.reload,
      to_product: nil,
      subscription_type: "studio"
    )
    assert_includes listed.limits_lowered, { name: "press_kits", from: 4, to: 2 }

    RecordingStudioStripe::Subscription.current_for(root_recording_id: @root.id).update!(status: "canceled")
    assert_equal 2, @workspace.billing.limit(:press_kits).included
    assert_equal 3, @workspace.billing.limit(:press_kits).used
    assert_raises(RecordingStudioStripe::PlanLimitReached) { record_press_kit!("After cancel") }
    assert_equal 3, @workspace.billing.limit(:press_kits).used
  end

  test "a zero limit with a purchase action shows the button and does not say this plan" do
    limits = @previous_limits.to_h.deep_stringify_keys
    limits["bonus_credits"] = {
      "label" => "Bonus credits",
      "aggregation" => "quantity",
      "subscription_type" => "studio",
      "action" => "purchase",
      "action_label" => "Buy credits",
      "action_url" => "/credits"
    }
    RecordingStudioStripe.configuration.limits = limits
    RecordingStudioStripe.register_limit_usage(:bonus_credits) { 0 }
    switch_to_root!(@root)

    get recording_studio_stripe.usage_path

    assert_response :success
    assert_includes response.body, "None on plan"
    assert_includes response.body, "Buy credits"
    assert_includes response.body, 'href="/credits"'
    refute_includes response.body, "this plan"
  end

  test "plan cards and gates print a byte quantity as a size" do
    configure_storage!(base: 2.gigabytes)
    @starter.assign_limits("storage_bytes" => 5.gigabytes)
    @starter.save!

    assert_includes @starter.limit_inclusion_lines, "5 GB storage"
    row = RecordingStudioStripe::GateCatalog.rows.find { |entry| entry.name == "storage_bytes" }
    assert_includes row.plans, "2 GB with no plan"

    get "/pricing"

    assert_response :success
    assert_includes response.body, "5 GB storage"
  end

  private

  def configure_storage!(base:)
    limits = @previous_limits.to_h.deep_stringify_keys
    limits["storage_bytes"] = {
      "label" => "Storage",
      "aggregation" => "quantity",
      "unit" => "bytes",
      "subscription_type" => "studio",
      "plan_line" => "%{quantity} storage",
      "no_plan_limit" => base
    }
    RecordingStudioStripe.configuration.limits = limits
    RecordingStudioStripe.register_limit_usage(:storage_bytes) { @usage }
  end

  def configure_press_kits!(base:)
    limits = @previous_limits.to_h.deep_stringify_keys
    limits["press_kits"] = limits["press_kits"].merge("no_plan_limit" => base)
    RecordingStudioStripe.configuration.limits = limits
  end

  def subscribe!
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: @starter.monthly_price)
  end

  def record_press_kit!(name)
    @root.record(PressKit) { |kit| kit.name = name }
  end
end
