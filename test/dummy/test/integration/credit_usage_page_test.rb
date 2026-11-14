# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class CreditUsagePageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @workspace = Workspace.create!(name: "Credit usage #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_owner_access!(recording: @root, actor: @user)
    sign_in @user
    switch_to_root!(@root)
    RecordingStudioStripe::Meter.sync_from_config!
  end

  test "usage page shows credits as used of the cap" do
    subscribe(included: 100)
    @workspace.billing.line(:studio).record_credits(
      amount: 63,
      breakdown: { "kind" => "attempt" },
      idempotency_key: "ai-attempt:page"
    )

    get recording_studio_stripe.usage_path

    assert_response :success
    assert_includes response.body, "Credits"
    assert_includes response.body, "63 of 100"
    refute_includes response.body, "63% used"
    refute_includes response.body, "fp-progress-fill--warning"
    refute_includes response.body, "fp-progress-fill--danger"
    refute_includes response.body, "% left"
  end

  test "usage page warns at 80 percent before the 15 percent status alert" do
    subscribe(included: 100)
    @workspace.billing.line(:studio).record_credits(
      amount: 80,
      breakdown: { "kind" => "attempt" },
      idempotency_key: "ai-attempt:warn-page"
    )

    get recording_studio_stripe.usage_path

    assert_response :success
    assert_includes response.body, "80 of 100"
    assert_includes response.body, "fp-progress-fill--warning"
    refute_includes response.body, "fp-progress-fill--danger"
    refute_includes response.body, "Near the limit"
  end

  test "usage page keeps the real total after credits run out" do
    subscribe(included: 100)
    @workspace.billing.line(:studio).record_credits(
      amount: 150,
      breakdown: { "kind" => "attempt" },
      idempotency_key: "ai-attempt:over-page"
    )

    get recording_studio_stripe.usage_path

    assert_response :success
    assert_includes response.body, "150 of 100"
    assert_includes response.body, "fp-progress-fill--danger"
    assert_includes response.body, "Over the limit"
    refute_includes response.body, "100% used"
    refute_includes response.body, "% left"
  end

  test "usage page uses a muted line when the credit total is zero" do
    subscribe(included: 0, extra_metadata: { "included_api_calls" => "10" })
    @workspace.billing.line(:studio).record_credits(
      amount: 5,
      breakdown: { "kind" => "attempt" },
      idempotency_key: "ai-attempt:zero-total"
    )

    get recording_studio_stripe.usage_path

    assert_response :success
    assert_includes response.body, "Credits"
    assert_includes response.body, "None on plan"
    refute_includes response.body, "None on this plan"
    refute_includes response.body, "Unlimited"
    refute_includes response.body, "% left"
    assert_select "[role=progressbar]", count: 1
  end

  private

  def subscribe(included:, extra_metadata: {})
    product = RecordingStudioStripe::Product.create!(
      stripe_id: "prod_#{SecureRandom.hex(6)}",
      name: "Usage #{SecureRandom.hex(3)}",
      kind: "plan",
      subscription_type: "studio"
    )
    metadata = extra_metadata.dup
    metadata["included_credits"] = included.to_s if included.positive?
    price = RecordingStudioStripe::Price.create!(
      stripe_id: "price_#{SecureRandom.hex(6)}",
      product: product,
      unit_amount: 1_000,
      currency: "usd",
      interval: "month",
      metadata: metadata
    )
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: price,
      email: "credits@example.com",
      current_period_start: 1.day.ago,
      current_period_end: 27.days.from_now
    )
  end
end
