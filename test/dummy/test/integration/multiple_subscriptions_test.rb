# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class MultipleSubscriptionsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_owner_access!(recording: @root, actor: @user)
    sign_in @user
    switch_to_root!(@root)
  end

  test "plans page groups Products by type" do
    get "/plans"

    assert_response :success
    assert_includes response.body, "Studio"
    assert_includes response.body, "Inbox"
    assert_includes response.body, "Starter"
    assert_includes response.body, "Pro"
    assert_includes response.body, "Inbox Plus"
    assert_includes response.body, "$25/month"
    assert_includes response.body, "$50/month"
    assert_select "[data-plan-group='studio'] a", text: "Monthly"
    assert_select "[data-plan-group='inbox'] a", text: "Monthly"
    assert_equal "studio", RecordingStudioStripe::Product.find_by!(name: "Pro").subscription_type
    assert_equal "inbox", RecordingStudioStripe::Product.find_by!(name: "Inbox").subscription_type
  end

  test "a workspace can hold one live plan per type on the same Customer" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    inbox = RecordingStudioStripe::Product.find_by!(name: "Inbox Plus").monthly_price

    post recording_studio_stripe.checkout_path, params: { price_id: pro.id }
    post recording_studio_stripe.checkout_path, params: { price_id: inbox.id }

    billing = @workspace.billing
    assert_equal 1, RecordingStudioStripe::Customer.where(root_recording_id: @root.id).count
    assert_equal 2, billing.active_lines.size
    assert_equal pro.id, billing.line(:studio).subscription.price_id
    assert_equal inbox.id, billing.line(:inbox).subscription.price_id
    assert billing.unlocked?(:generate_image)
    assert billing.unlocked?(:export_csv)
    refute billing.line(:studio).unlocked?(:export_csv)
    refute billing.line(:inbox).unlocked?(:generate_image)
  end

  test "choosing a plan in an empty type starts checkout instead of changing the other type" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    inbox = RecordingStudioStripe::Product.find_by!(name: "Inbox").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)

    get "/plans"

    assert_response :success
    assert_includes response.body, "Current plan"
    assert_includes response.body, "Choose plan"

    post recording_studio_stripe.checkout_path, params: { price_id: inbox.id }

    assert_equal pro.id, @workspace.billing.line(:studio).subscription.price_id
    assert_equal inbox.id, @workspace.billing.line(:inbox).subscription.price_id
  end

  test "upgrade only moves the matching type" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    inbox = RecordingStudioStripe::Product.find_by!(name: "Inbox").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: starter)
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: inbox)

    patch recording_studio_stripe.subscription_path, params: { price_id: pro.id }

    assert_equal pro.id, @workspace.billing.line(:studio).subscription.price_id
    assert_equal inbox.id, @workspace.billing.line(:inbox).subscription.price_id
    refute @workspace.billing.line(:studio).subscription.scheduled_downgrade?
  end

  test "cancel stops one type and leaves the other" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    inbox = RecordingStudioStripe::Product.find_by!(name: "Inbox Plus").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: inbox)

    post recording_studio_stripe.subscription_cancel_path, params: { subscription_type: "studio" }

    follow_redirect!
    assert_predicate @workspace.billing.line(:studio).subscription, :canceling?
    refute_predicate @workspace.billing.line(:inbox).subscription, :canceling?
    assert_includes response.body, "Studio"
    assert_includes response.body, "Inbox"
    assert_includes response.body, "Pro"
    assert_includes response.body, "Inbox Plus"
  end

  test "meters stay on the type whose period they belong to" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    inbox = RecordingStudioStripe::Product.find_by!(name: "Inbox Plus").monthly_price
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: pro,
      current_period_start: 2.days.ago,
      current_period_end: 28.days.from_now
    )
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: inbox,
      current_period_start: 10.days.ago,
      current_period_end: 20.days.from_now
    )

    studio_tokens = @workspace.billing.line(:studio).meter(:ai_tokens)
    inbox_tokens = @workspace.billing.line(:inbox).meter(:ai_tokens)
    inbox_calls = @workspace.billing.line(:inbox).meter(:api_calls)

    assert_equal 10_000_000, studio_tokens.included
    assert_equal 0, inbox_tokens.included
    assert_equal 50_000, inbox_calls.included
  end

  test "assign remaps implied plan rows when the host has one type" do
    previous = RecordingStudioStripe.configuration.subscription_types
    RecordingStudioStripe.configuration.subscription_types = { "kits" => { "label" => "Kits" } }
    product = RecordingStudioStripe::Product.find_by!(name: "Pro")
    product.update_column(:subscription_type, "plan")

    RecordingStudioStripe::AssignSubscriptionTypes.call

    assert_equal "kits", product.reload.subscription_type
  ensure
    RecordingStudioStripe.configuration.subscription_types = previous
    RecordingStudioStripe::AssignSubscriptionTypes.call
    RecordingStudioStripe::SeedDemoCatalog.call
  end
end
