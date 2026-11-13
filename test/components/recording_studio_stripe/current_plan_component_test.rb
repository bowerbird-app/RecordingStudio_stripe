# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../../dummy/test/test_helper"

module RecordingStudioStripe
  class CurrentPlanComponentTest < ActiveSupport::TestCase
    setup do
      RecordingStudioStripe::SeedDemoCatalog.call
      @user = User.find_or_create_by!(email: "plan-card@example.com") do |user|
        user.password = "Password"
        user.password_confirmation = "Password"
      end
      @workspace = Workspace.find_or_create_by!(name: "Plan Card Workspace")
      @root = RecordingStudio.root_recording_for(@workspace)
      grant_owner_access!(recording: @root, actor: @user)
      @pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
      @starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
      travel_to Time.utc(2026, 11, 13, 12, 0, 0)
      RecordingStudioStripe::ApplySubscription.call(
        root_recording: @root,
        price: @pro,
        current_period_end: Time.utc(2026, 12, 4)
      )
      @subscription = RecordingStudioStripe::Subscription.current_for(
        root_recording_id: @root.id,
        subscription_type: "studio"
      )
    end

    teardown do
      travel_back
    end

    test "active plan uses one status badge and the renewal line" do
      html = render_plan

      assert_includes html, ">Active<"
      assert_includes html, "$29/month"
      assert_includes html, "Renews in 21 days"
      refute_includes html, "$29/month (Renews"
      refute_includes html, ">Current<"
      refute_includes html, "Trial ending soon"
      refute_includes html, "Plan canceled"
      refute_includes html, "Ends this period"
      assert_includes html, ">Studio<"
      assert_includes html, "Change plan"
      assert_includes html, ">Cancel<"
    end

    test "trialing plan shows the trial badge and a trial-ending alert when the trial is close" do
      @subscription.update!(status: "trialing", current_period_end: Time.utc(2026, 11, 16))

      html = render_plan

      assert_includes html, ">Trial<"
      assert_includes html, "Trial ends in 3 days"
      assert_includes html, "Trial ending soon"
      assert_includes html, "Add a payment method before the trial ends"
      refute_includes html, ">Active<"
      refute_includes html, "Plan canceled"
      refute_includes html, "$29/month (Trial ends"
    end

    test "a long trial does not use the trial-ending alert" do
      @subscription.update!(status: "trialing", current_period_end: Time.utc(2026, 12, 4))

      html = render_plan

      assert_includes html, ">Trial<"
      assert_includes html, "Trial ends in 21 days"
      refute_includes html, "Trial ending soon"
    end

    test "past due uses the past due preset and an update card form" do
      @subscription.update!(status: "past_due")

      html = render_plan

      assert_includes html, ">Past due<"
      assert_includes html, "Update your payment method to keep this workspace on its plan."
      refute_includes html, "Payment failed"
      refute_includes html, "Plan canceled"
      refute_includes html, "Renews in"
      assert_select_form(html, action: "/billing/portal", label: "Update card")
    end

    test "canceled is the canceled preset and not an end-of-period plan" do
      @subscription.update!(status: "canceled", cancel_at_period_end: false)

      html = render_plan

      assert_includes html, ">Canceled<"
      assert_includes html, "Plan canceled"
      assert_includes html, "This workspace is no longer on a paid plan."
      refute_includes html, "Ends this period"
      refute_includes html, "Keep this plan"
      refute_includes html, ">Cancel<"
      refute_includes html, "Payment failed"
    end

    test "cancel at period end keeps the active badge, the end notice, and keep this plan" do
      @subscription.update!(status: "active", cancel_at_period_end: true, current_period_end: Time.utc(2026, 12, 4))

      html = render_plan

      assert_includes html, ">Active<"
      assert_includes html, "Ends this period"
      assert_includes html, "This plan runs until December 04, 2026."
      refute_includes html, ">Canceled<"
      refute_includes html, "Plan canceled"
      refute_includes html, "Renews in"
      assert_select_form(html, action: "/billing/subscription/resume", label: "Keep this plan")
      refute_includes html, ">Cancel<"
    end

    test "a scheduled change keeps the active badge, the change notice, and stay on this plan" do
      @subscription.update!(status: "active", cancel_at_period_end: false, scheduled_price: @starter)

      html = render_plan

      assert_includes html, ">Active<"
      assert_includes html, "Change scheduled"
      assert_includes html, "Next period switches to Starter."
      refute_includes html, ">Canceled<"
      refute_includes html, "Plan canceled"
      refute_includes html, "Ends this period"
      assert_select_form(html, action: "/billing/subscription/keep", label: "Stay on Pro")
    end

    test "over the limit and near the limit use custom status alerts" do
      9.times { |index| @root.record(PressKit) { |kit| kit.name = "Near #{index}" } }

      near = render_plan
      assert_includes near, "Near the limit"
      assert_includes near, "You’re close to the Press kits cap."
      refute_includes near, "Over the limit"

      @subscription.update!(price: @starter)

      over = render_plan
      assert_includes over, "Over the limit"
      assert_includes over, "This plan is past its Press kits cap. Archive some, or upgrade."
      refute_includes over, "Near the limit"
    end

    private

    def render_plan
      ApplicationController.render(
        RecordingStudioStripe::CurrentPlanComponent.new(subscription: @subscription.reload),
        layout: false
      )
    end

    def assert_select_form(html, action:, label:)
      fragment = Nokogiri::HTML.fragment(html)
      form = fragment.at_css("form[action='#{action}']")
      assert form, "expected a form posting to #{action}"
      assert_equal 1, form.css("button[type='submit'], input[type='submit']").size
      assert_includes form.text, label
    end
  end
end
