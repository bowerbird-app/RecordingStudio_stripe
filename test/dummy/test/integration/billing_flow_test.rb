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
    switch_to_root!(@root)
  end

  test "plans page lists monthly Products" do
    get "/plans"

    assert_response :success
    assert_includes response.body, "Pick a plan"
    assert_includes response.body, "Studio"
    assert_includes response.body, "Inbox"
    assert_includes response.body, "Pro"
    assert_includes response.body, "Starter"
    assert_includes response.body, "Inbox Plus"
    assert_includes response.body, "$29/month"
    assert_includes response.body, "$9/month"
    assert_includes response.body, "$25/month"
    assert_includes response.body, "10m ai tokens"
    assert_includes response.body, "Monthly"
    assert_includes response.body, "Yearly"
    assert_includes response.body, "[border-radius:var(--tabs-pill-corner-radius)]"
    refute_includes response.body, "[&>*]:border-r-0"
    refute_includes response.body, "border-b border-[var(--card-border-color)]"
    refute_includes response.body, "border-t border-[var(--card-border-color)]"
    assert_select "body[data-theme='rounded']", count: 1
    assert_select "html[data-theme='rounded']", count: 1
    assert_select "[data-plans-align='left']", count: 1
    assert_includes response.body, "justify-start"
    assert_select "form[action*='checkout'][data-turbo=false]"
  end

  test "public pricing page centers the plan cards" do
    sign_out @user
    get "/pricing"

    assert_response :success
    assert_includes response.body, "Pick a plan"
    assert_includes response.body, "Studio"
    assert_includes response.body, "Inbox"
    assert_includes response.body, "Pro"
    assert_includes response.body, "Starter"
    assert_includes response.body, "$29/month"
    assert_select "html[data-theme='rounded']", count: 1
    assert_select "[data-plans-align='center']", count: 1
    assert_includes response.body, "justify-center"
    refute_includes response.body, "data-recording-studio-default-layout"
  end

  test "public pricing page shows yearly Prices" do
    sign_out @user
    get "/pricing", params: { interval: "year" }

    assert_response :success
    assert_includes response.body, "$290/year"
    assert_includes response.body, "$90/year"
    assert_select "[data-plans-align='center']", count: 1
  end

  test "plans page shows yearly Prices on the same Products" do
    get "/plans", params: { interval: "year" }

    assert_response :success
    assert_includes response.body, "Pro"
    assert_includes response.body, "Starter"
    assert_includes response.body, "Inbox Plus"
    assert_includes response.body, "$290/year"
    assert_includes response.body, "$90/year"
    assert_includes response.body, "$250/year"
  end

  test "plans page toggles monthly and yearly per group" do
    get "/plans", params: { interval: { studio: "year" } }

    assert_response :success
    assert_select "[data-plan-group='studio']", count: 1
    assert_select "[data-plan-group='inbox']", count: 1
    assert_select "[data-plan-group='studio'] a", text: "Yearly"
    assert_select "[data-plan-group='inbox'] a", text: "Yearly"
    assert_select "[aria-label='Studio yearly']"
    assert_select "[aria-label='Inbox monthly']"
    assert_includes response.body, "$290/year"
    assert_includes response.body, "$90/year"
    assert_includes response.body, "$25/month"
    assert_includes response.body, "$50/month"
    refute_includes response.body, "$250/year"
    refute_includes response.body, "$500/year"
  end

  test "plans component rejects an unknown align" do
    error = assert_raises ArgumentError do
      RecordingStudioStripe::PlansComponent.new(
        products: [],
        interval: "month",
        monthly_href: "/plans",
        yearly_href: "/plans?interval=year",
        align: :right
      )
    end

    assert_match(/left or :center/, error.message)
  end

  test "checkout in local mode starts a subscription" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    post recording_studio_stripe.checkout_path, params: { price_id: price.id }

    assert_redirected_to %r{/billing}
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Pro"
    assert_predicate @workspace.billing.subscription, :active?
    assert @workspace.billing.unlocked?(:generate_image)
    refute @workspace.billing.unlocked?(:export_csv)
    assert RecordingStudioAccessible.authorized_action?(
      actor: @user,
      action: :generate_image,
      recording: @root
    )
    refute RecordingStudioAccessible.authorized_action?(
      actor: @user,
      action: :export_csv,
      recording: @root
    )
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

  test "billing page shows usage percent" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)

    get recording_studio_stripe.root_path

    assert_response :success
    assert_includes response.body, "Studio usage"
    assert_includes response.body, "AI tokens"
    assert_includes response.body, "0%"
    assert_includes response.body, "+5m ai tokens"
    refute_includes response.body, "10m left"
    refute_includes response.body, "Included 10m"
    assert_includes response.body, "md:grid-cols-2"
    assert_includes response.body, "badge-primary-background-color"
  end

  test "buying an extra pack increases remaining" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    pack = RecordingStudioStripe::Price.one_time.find_by!("metadata ->> 'allowance' = '5000000'")
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)

    post recording_studio_stripe.allowances_path, params: { price_id: pack.id }

    follow_redirect!
    assert_equal 15_000_000, @workspace.billing.meter(:ai_tokens).remaining
  end

  test "billing hides manage billing before a customer exists" do
    get recording_studio_stripe.root_path

    assert_response :success
    refute_includes response.body, "Manage billing on Stripe"
  end

  test "manage billing shows when a customer exists without an active plan" do
    RecordingStudioStripe::EnsureCustomer.call(root_recording: @root, email: @user.email)

    get recording_studio_stripe.root_path

    assert_response :success
    assert_includes response.body, "No plan yet"
    assert_includes response.body, "Manage billing on Stripe"
  end

  test "manage billing shows after checkout and stays local without keys" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    post recording_studio_stripe.checkout_path, params: { price_id: price.id }
    follow_redirect!

    assert_response :success
    assert_includes response.body, "Manage billing on Stripe"
    assert_includes response.body, "credit-card"
    assert_includes response.body, recording_studio_stripe.portal_path

    post recording_studio_stripe.portal_path

    assert_redirected_to %r{/billing}
    follow_redirect!
    assert_includes response.body, "Invoices and cards live in Stripe. Add keys to open them."
  end

  test "portal redirects to Stripe when a client is set" do
    previous_client = RecordingStudioStripe.configuration.client
    RecordingStudioStripe.configuration.client = RecordingStudioStripe::Testing::Client.new
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)

    post recording_studio_stripe.portal_path

    assert_redirected_to %r{\Ahttps://billing.stripe.test}
  ensure
    RecordingStudioStripe.configuration.client = previous_client
  end

  test "view access can see billing and cannot open the portal" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)
    viewer = User.find_or_create_by!(email: "viewer@example.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    grant_owner_access!(recording: @root, actor: viewer, role: :view)
    sign_out @user
    sign_in viewer
    switch_to_root!(@root)

    get recording_studio_stripe.root_path

    assert_response :success
    refute_includes response.body, "Manage billing on Stripe"

    post recording_studio_stripe.portal_path

    assert_response :forbidden
  end

  test "starter does not open generate_image" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: starter)

    refute @workspace.billing.unlocked?(:generate_image)
    refute RecordingStudioAccessible.authorized_action?(
      actor: @user,
      action: :generate_image,
      recording: @root
    )
  end

  test "home shows paywalls off without a plan and on after Pro" do
    get "/"

    assert_response :success
    assert_includes response.body, "What this plan opens"
    assert_includes response.body, "Generate an image"
    assert_includes response.body, "Export CSV"
    refute RecordingStudioAccessible.authorized_action?(
      actor: @user,
      action: :generate_image,
      recording: @root
    )

    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)

    get "/"

    assert_response :success
    assert RecordingStudioAccessible.authorized_action?(
      actor: @user,
      action: :generate_image,
      recording: @root
    )
  end
end
