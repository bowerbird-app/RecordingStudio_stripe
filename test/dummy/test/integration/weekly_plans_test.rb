# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class WeeklyPlansTest < ActionDispatch::IntegrationTest
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
    @starter = RecordingStudioStripe::Product.find_by!(name: "Starter")
    @weekly = RecordingStudioStripe::CreatePrice.call(
      product: @starter,
      unit_amount: 700,
      currency: "usd",
      interval: "week"
    )
  end

  test "weekly pill shows only on the group that has a weekly Price" do
    get "/plans"

    assert_response :success
    assert_select "[data-plan-group='studio'] a", text: "Weekly"
    assert_select "[data-plan-group='inbox'] a", text: "Weekly", count: 0
    assert_select "[data-plan-group='studio'] a", text: "Monthly"
    assert_select "[data-plan-group='inbox'] a", text: "Yearly"
    assert_select "[aria-label='Studio weekly']"
    assert_select "[aria-label='Inbox weekly']", count: 0
  end

  test "weekly cards show only Products that have a weekly Price" do
    get "/plans", params: { interval: { studio: "week" } }

    assert_response :success
    assert_select "[data-plan-group='studio'] p", text: "$7/wk"
    assert_select "[aria-label='Studio weekly']"
    assert_select "[data-plan-group='inbox'] p", text: "$25/mo"
    assert_select "[data-plan-group='inbox'] a", text: "Weekly", count: 0
    assert_equal ["Starter"], css_select("[data-plan-group='studio'] h3").map(&:text)
    refute_includes response.body, "No week Price yet"
    assert_equal @weekly, @starter.price_for("week")
    assert_equal 3033, @weekly.monthly_unit_amount
  end

  test "stripe_plan_intervals lists priced intervals and honors a limit" do
    helper = Object.new.extend(RecordingStudioStripe::ApplicationHelper)
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro")

    assert_equal %w[week month year], helper.stripe_plan_intervals([@starter])
    assert_equal %w[month year], helper.stripe_plan_intervals([pro])
    assert_equal %w[week], helper.stripe_plan_intervals([@starter, pro], intervals: %w[week])
  end

  test "a week-only page stays empty when nothing is priced weekly" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro")
    html = ApplicationController.render(
      RecordingStudioStripe::PlansComponent.new(
        products: [pro],
        weekly_href: "/plans?interval=week",
        monthly_href: "/plans",
        yearly_href: "/plans?interval=year",
        intervals: %w[week]
      )
    )

    assert_includes html, "No prices yet"
    refute_includes html, ">Monthly<"
    refute_includes html, "$29"
  end

  test "a priced interval stays hidden when the page limits intervals" do
    html = ApplicationController.render(
      RecordingStudioStripe::PlansComponent.new(
        products: [@starter],
        weekly_href: "/plans?interval=week",
        monthly_href: "/plans",
        yearly_href: "/plans?interval=year",
        intervals: %w[week]
      )
    )

    assert_includes html, ">Weekly<"
    assert_includes html, "$7"
    assert_includes html, "/wk"
    refute_includes html, ">Monthly<"
    refute_includes html, ">Yearly<"
  end

  test "yearly hides when no Product has a yearly Price" do
    RecordingStudioStripe::Price.where(interval: "year").update_all(active: false)

    get "/plans"

    assert_response :success
    assert_select "a", text: "Yearly", count: 0
    assert_select "[data-plan-group='studio'] a", text: "Monthly"
    assert_select "[data-plan-group='studio'] p", text: "$9/mo"
    assert_select "[data-plan-group='inbox'] p", text: "$25/mo"
  end

  test "local checkout on a weekly Price ends one week out" do
    travel_to Time.utc(2026, 9, 25, 12, 0, 0) do
      post recording_studio_stripe.checkout_path, params: { price_id: @weekly.id }
    end

    assert_redirected_to %r{/billing}
    subscription = @workspace.billing.line("studio").subscription
    assert_equal @weekly.id, subscription.price_id
    assert_equal Time.utc(2026, 10, 2, 12, 0, 0), subscription.current_period_end
  end

  test "create price rejects a day interval and a webhook can still store one" do
    error = assert_raises(RecordingStudioStripe::InvalidPrice) do
      RecordingStudioStripe::CreatePrice.call(product: @starter, unit_amount: 500, interval: "day")
    end
    assert_includes error.message, "week, month, or year"

    stripe_price = Struct.new(:id, :product, :unit_amount, :currency, :recurring, :active, :metadata).new(
      "price_webhook_day",
      @starter.stripe_id,
      500,
      "usd",
      { "interval" => "day" },
      true,
      {}
    )
    stored = RecordingStudioStripe::UpsertPrice.call(stripe_price)

    assert_equal "day", stored.interval
    assert_equal @starter, stored.product
  end
end
