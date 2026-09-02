# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class BillingFlowTest < ActionDispatch::IntegrationTest
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
  end

  test "plans page lists monthly Products" do
    get plans_path

    assert_response :success
    assert_includes response.body, "Pick a plan"
    assert_includes response.body, "Pro"
    assert_includes response.body, "$29/month"
    assert_includes response.body, "10m ai tokens"
  end

  test "checkout in local mode starts a subscription" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    post recording_studio_stripe.checkout_path, params: { price_id: price.id }

    assert_redirected_to %r{/billing}
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Pro"
    assert_predicate @workspace.billing.subscription, :active?
  end

  test "upgrade takes effect immediately" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: starter)

    patch recording_studio_stripe.subscription_path, params: { price_id: pro.id }

    follow_redirect!
    assert_equal pro.id, @workspace.billing.subscription.price_id
    refute @workspace.billing.subscription.scheduled_downgrade?
  end

  test "downgrade schedules for renewal" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)

    patch recording_studio_stripe.subscription_path, params: { price_id: starter.id }

    follow_redirect!
    subscription = @workspace.billing.subscription
    assert_equal pro.id, subscription.price_id
    assert_equal starter.id, subscription.scheduled_price_id
  end

  test "cancel stays active until period end" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)

    post recording_studio_stripe.subscription_cancel_path

    follow_redirect!
    assert_predicate @workspace.billing.subscription, :canceling?
    assert_predicate @workspace.billing.subscription, :active?
  end

  test "meter remaining is included plus purchased minus usage" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    pack = RecordingStudioStripe::Price.one_time.find_by!("metadata ->> 'allowance' = '5000000'")
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)
    RecordingStudioStripe::ApplyAllowance.call(root_recording: @root, price: pack)

    meter = @workspace.billing.meter(:ai_tokens)
    meter.record(1_000_000)

    assert_equal 10_000_000, meter.included
    assert_equal 5_000_000, meter.purchased
    assert_equal 1_000_000, meter.usage
    assert_equal 14_000_000, meter.remaining
    assert meter.available?(14_000_000)
    refute meter.available?(14_000_001)
  end

  test "billing page shows remaining copy" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)

    get recording_studio_stripe.root_path

    assert_response :success
    assert_includes response.body, "Usage this period"
    assert_includes response.body, "AI tokens"
    assert_includes response.body, "+5m ai tokens"
  end

  test "buying an extra pack increases remaining" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    pack = RecordingStudioStripe::Price.one_time.find_by!("metadata ->> 'allowance' = '5000000'")
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)

    post recording_studio_stripe.allowances_path, params: { price_id: pack.id }

    follow_redirect!
    assert_equal 15_000_000, @workspace.billing.meter(:ai_tokens).remaining
  end
end
