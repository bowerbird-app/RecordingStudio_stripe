# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class PublicPlansTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    @root = RecordingStudio.create_root_recording!(@workspace, actor: root_actor)
    grant_owner_access!(recording: @root, actor: @user, role: :admin)
  end

  test "plans stay signed in when public plans are off" do
    configuration = RecordingStudioStripe.configuration
    previous = configuration.public_plans
    configuration.public_plans = false

    get "/plans"

    assert_redirected_to new_user_session_path
  ensure
    configuration.public_plans = previous
  end

  test "guest plans list active prices and link sign up without billing data" do
    with_public_plans("/users/sign_up") do
      refute_billing_lookup { get "/plans" }

      assert_response :success
      assert_includes response.body, "Pricing"
      assert_select "[data-plan-group='studio'] h3", text: "Starter"
      assert_select "[data-plan-group='studio'] p", text: "$9/mo"
      assert_select "[data-plan-group='studio'] p", text: "$29/mo$1trial"
      assert_signup_links(6, "/users/sign_up")
      refute_guest_billing(response.body)
      refute_includes response.body, "AI token packs"

      get "/plans", params: { interval: "year" }

      assert_response :success
      assert_select "[data-plan-group='studio'] p", text: "$90/yr"
      assert_select "[data-plan-group='studio'] p", text: "$290/yr$1trial"
      assert_signup_links(6, "/users/sign_up")
      refute_guest_billing(response.body)
    end
  end

  test "guest sign up uses a callable path and does not add a plan or return_to" do
    with_public_plans(-> { main_app.new_user_registration_path }) do
      get "/plans"

      assert_response :success
      assert_signup_links(6, "/users/sign_up")
    end
  end

  test "guest plans hide inactive products and inactive prices" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter")
    monthly = starter.monthly_price
    monthly.update!(active: false)
    team = RecordingStudioStripe::Product.find_by!(name: "Team")
    team.update!(active: false)

    with_public_plans("/users/sign_up") do
      get "/plans"

      assert_response :success
      assert_select "[data-plan-group='studio'] h3", text: "Pro"
      assert_select "[data-plan-group='studio'] h3", text: "Starter", count: 0
      assert_select "[data-plan-group='studio'] h3", text: "Team", count: 0
      assert_select "[data-plan-group='studio'] p", text: "$9/mo", count: 0
      assert_select "[data-plan-group='studio'] p", text: "$79/mo", count: 0
      assert_signup_links(4, "/users/sign_up")
      refute_includes response.body, monthly.stripe_id
      refute_includes response.body, team.monthly_price.stripe_id
      refute_guest_billing(response.body)
    end
  end

  test "a subscribed workspace is not visible to a guest" do
    sign_in @user
    switch_to_root!(@root)
    price = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    post recording_studio_stripe.checkout_path, params: { price_id: price.id }
    assert_redirected_to %r{/billing}

    customer = RecordingStudioStripe::Customer.find_by!(root_recording_id: @root.id)
    subscription = @workspace.billing.line("studio").subscription
    sign_out @user

    with_public_plans("/users/sign_up") do
      refute_billing_lookup { get "/plans" }

      assert_response :success
      assert_signup_links(6, "/users/sign_up")
      refute_guest_billing(response.body)
      refute_includes response.body, customer.stripe_id
      refute_includes response.body, subscription.stripe_id
      refute_includes response.body, customer.email
    end
  end

  test "guest plans with no signup path still omit checkout" do
    with_public_plans(nil) do
      get "/plans"

      assert_response :success
      assert_select "a", text: "Sign up", count: 0
      refute_guest_billing(response.body)
    end
  end

  test "signed-in workspace plans stay on checkout when public plans are on" do
    sign_in @user
    switch_to_root!(@root)
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    with_public_plans("/users/sign_up") do
      get "/plans"

      assert_response :success
      assert_select "input[name=price_id][value='#{price.id}']"
      assert_select "form[action*='checkout']"
      assert_includes response.body, "Try now"
      assert_includes response.body, "Choose plan"
      assert_select "a[href='/users/sign_up']", count: 0

      post recording_studio_stripe.checkout_path, params: { price_id: price.id }

      assert_redirected_to %r{/billing}
      follow_redirect!
      get "/plans"

      assert_response :success
      assert_includes response.body, "Current plan"
      assert_select "a[href='/users/sign_up']", count: 0
    end
  end

  test "signed-in actor without a billing root sees guest plans" do
    previous = nil
    sign_in @user
    configuration = RecordingStudioStripe.configuration
    previous = configuration.current_root_recording
    configuration.current_root_recording = -> { nil }

    with_public_plans("/users/sign_up") do
      refute_billing_lookup { get "/plans" }

      assert_response :success
      assert_signup_links(6, "/users/sign_up")
      refute_guest_billing(response.body)
    end
  ensure
    RecordingStudioStripe.configuration.current_root_recording = previous
  end

  test "a view role can read workspace plans and cannot checkout when public plans are on" do
    viewer = User.find_or_create_by!(email: "viewer-public-plans@example.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    grant_owner_access!(recording: @root, actor: viewer, role: :view)
    sign_in viewer
    switch_to_root!(@root)
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    with_public_plans("/users/sign_up") do
      get "/plans"

      assert_response :success
      assert_select "form[action*='checkout']"
      assert_select "a[href='/users/sign_up']", count: 0

      post recording_studio_stripe.checkout_path, params: { price_id: price.id }

      assert_response :forbidden
      assert_equal RecordingStudioStripe::Copy.t("alerts.no_access"), response.body
    end
  end

  test "public plans does not open billing checkout or the portal" do
    with_public_plans("/users/sign_up") do
      get "/billing"
      assert_redirected_to new_user_session_path

      get "/billing/usage"
      assert_redirected_to new_user_session_path

      post recording_studio_stripe.checkout_path, params: { price_id: "unused" }
      assert_redirected_to new_user_session_path

      post recording_studio_stripe.portal_path
      assert_redirected_to new_user_session_path
    end
  end

  private

  def with_public_plans(path)
    configuration = RecordingStudioStripe.configuration
    previous_flag = configuration.public_plans
    previous_path = configuration.public_plans_signup_path
    configuration.public_plans = true
    configuration.public_plans_signup_path = path
    yield
  ensure
    configuration.public_plans = previous_flag
    configuration.public_plans_signup_path = previous_path
  end

  def assert_signup_links(count, href)
    links = css_select("a[href='#{href}']")
    assert_equal count, links.size, response.body
    links.each do |link|
      assert_equal "Sign up", link.text.squish
      assert_equal href, link["href"]
      refute_includes link["href"], "return_to"
      refute_includes link["href"], "plan"
    end
  end

  def refute_guest_billing(body)
    assert_select "input[name=price_id]", count: 0
    assert_select "form[action*='checkout']", count: 0
    assert_select "form[action*='portal']", count: 0
    refute_includes body, "Current plan"
    refute_includes body, "Choose plan"
    refute_includes body, "Try now"
    RecordingStudioStripe::Price.pluck(:stripe_id).each do |stripe_id|
      refute_includes body, stripe_id
    end
    RecordingStudioStripe::Customer.pluck(:stripe_id).each do |stripe_id|
      refute_includes body, stripe_id
    end
  end

  def refute_billing_lookup
    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      queries << sql if sql.match?(/recording_studio_stripe_(subscriptions|customers)/)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    assert_empty queries, queries
  end
end
