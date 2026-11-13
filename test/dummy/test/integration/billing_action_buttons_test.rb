# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class BillingActionButtonsTest < ActionDispatch::IntegrationTest
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
    @pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    @starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: @pro,
      email: @user.email,
      current_period_end: Time.utc(2026, 12, 4)
    )
  end

  test "plan confirm is one submit" do
    html = render_component(RecordingStudioStripe::PlanChangeComponent.new(change: plan_change))

    assert_no_nested_buttons(html)
    assert_single_submit(
      html,
      action: "/billing/subscription",
      method: "patch",
      hidden: { "price_id" => @starter.id },
      label: "Downgrade"
    )
  end

  test "cancel confirm is one submit" do
    html = render_component(RecordingStudioStripe::CancelPlanComponent.new(cancel: cancel_plan))

    assert_no_nested_buttons(html)
    assert_single_submit(
      html,
      action: "/billing/subscription/cancel",
      hidden: { "subscription_type" => "studio" },
      label: "Cancel at period end"
    )
  end

  test "allowance buy is one checkout submit" do
    price = RecordingStudioStripe::Price.one_time.find_by!("metadata ->> 'allowance' = '5000000'")
    html = render_component(RecordingStudioStripe::AllowanceCardComponent.new(price: price))

    assert_no_nested_buttons(html)
    assert_single_submit(
      html,
      action: "/billing/allowances",
      turbo: false,
      hidden: { "price_id" => price.id },
      label: "Add this pack"
    )
  end

  test "update card is one portal submit" do
    subscription.update!(status: "past_due")
    html = render_component(RecordingStudioStripe::CurrentPlanComponent.new(subscription: subscription.reload))

    assert_no_nested_buttons(html)
    assert_single_submit(html, action: "/billing/portal", turbo: false, label: "Update card")
    assert_includes html, "Change plan"
    assert_includes html, "Cancel"
  end

  test "stay on plan is one submit" do
    subscription.update!(scheduled_price: @starter)
    html = render_component(RecordingStudioStripe::CurrentPlanComponent.new(subscription: subscription.reload))

    assert_no_nested_buttons(html)
    assert_single_submit(
      html,
      action: "/billing/subscription/keep",
      hidden: { "subscription_type" => "studio" },
      label: "Stay on Pro"
    )
  end

  test "keep this plan is one submit" do
    subscription.update!(cancel_at_period_end: true)
    html = render_component(RecordingStudioStripe::CurrentPlanComponent.new(subscription: subscription.reload))

    assert_no_nested_buttons(html)
    assert_single_submit(
      html,
      action: "/billing/subscription/resume",
      hidden: { "subscription_type" => "studio" },
      label: "Keep this plan"
    )
    refute_includes html, ">Cancel<"
  end

  test "billing page manage button is one portal submit" do
    get recording_studio_stripe.root_path

    assert_response :success
    assert_no_nested_buttons(response.body)
    assert_single_submit(
      response.body,
      action: "/billing/portal",
      turbo: false,
      label: "Manage billing on Stripe"
    )
  end

  test "plan change and cancel pages render one submit" do
    get recording_studio_stripe.subscription_change_path(price_id: @starter.id)

    assert_response :success
    assert_no_nested_buttons(response.body)
    assert_single_submit(
      response.body,
      action: "/billing/subscription",
      method: "patch",
      hidden: { "price_id" => @starter.id },
      label: "Downgrade"
    )

    get recording_studio_stripe.subscription_cancel_confirm_path(subscription_type: "studio")

    assert_response :success
    assert_no_nested_buttons(response.body)
    assert_single_submit(
      response.body,
      action: "/billing/subscription/cancel",
      hidden: { "subscription_type" => "studio" },
      label: "Cancel at period end"
    )
  end

  test "dummy admin switch is one submit" do
    admin_root = AdminRoot.find_or_create_by!(name: "Studio Admin")
    admin_recording = RecordingStudio.root_recording_for(admin_root)

    get "/"

    assert_response :success
    assert_no_nested_buttons(response.body)
    assert_single_submit(
      response.body,
      action: "/recording_studio_root_switchable/v1/root_switch",
      method: "patch",
      hidden: {
        "scope" => "all_workspaces",
        "root_switch[root_recording_id]" => admin_recording.id,
        "root_switch[return_to]" => "/admin"
      },
      label: "Admin"
    )
  end

  private

  def subscription
    RecordingStudioStripe::Subscription.current_for(root_recording_id: @root.id, subscription_type: "studio")
  end

  def plan_change
    RecordingStudioStripe::PlanChange.new(subscription: subscription, price: @starter)
  end

  def cancel_plan
    RecordingStudioStripe::CancelPlan.new(subscription: subscription)
  end

  def render_component(component)
    ApplicationController.render(component, layout: false)
  end

  def assert_no_nested_buttons(html)
    depth = 0
    html.to_s.scan(/<\/?button\b[^>]*>/i) do
      tag = Regexp.last_match(0)
      index = Regexp.last_match.begin(0)
      if tag.match?(%r{\A</}i)
        depth -= 1
        flunk "button closed too early near #{html[index, 120]}" if depth.negative?
      else
        depth += 1
        flunk "nested button near #{html[index, 220]}" if depth > 1
      end
    end
    flunk "unclosed button" unless depth.zero?
  end

  def assert_single_submit(html, action:, label:, method: "post", turbo: nil, hidden: {})
    form = form_source(html, action)
    assert form, "missing form #{action}"
    assert_includes form, label
    assert_equal 1, form.scan(/<button\b/i).size, form
    assert_includes form, 'type="submit"'
    assert_includes form, "inline-flex"
    if turbo == false
      assert_includes form, 'data-turbo="false"'
    else
      refute_includes form, "data-turbo"
    end
    if method == "post"
      refute_match(/name="_method"/, form)
    else
      assert_includes form, %(name="_method" value="#{method}")
    end
    hidden.each do |name, value|
      assert_match(/name="#{Regexp.escape(name.to_s)}"[^>]*value="#{Regexp.escape(value.to_s)}"/, form)
    end
  end

  def form_source(html, action)
    html.to_s.scan(/<form\b[^>]*>.*?<\/form>/m).find { |form| form.include?(action) }
  end
end
