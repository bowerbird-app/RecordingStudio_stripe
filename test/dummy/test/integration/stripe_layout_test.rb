# frozen_string_literal: true

require "test_helper"

class StripeLayoutTest < ActiveSupport::TestCase
  setup do
    @stripe = RecordingStudioStripe.configuration
    @core = RecordingStudio.configuration
    @previous_stripe = @stripe.layout
    @previous_core = @core.layout
  end

  teardown do
    @stripe.layout = @previous_stripe
    @core.layout = @previous_core
  end

  test "nil layout falls through to the recording studio layout and then the default" do
    @stripe.layout = nil
    @core.layout = nil
    controller = RecordingStudioStripe::PlansController.new

    assert_equal "recording_studio/default_layout", controller.recording_studio_resolved_layout

    @core.layout = "host_shell"
    assert_equal "host_shell", controller.recording_studio_resolved_layout
  end

  test "a string layout name is used as given" do
    @stripe.layout = "focus"
    controller = RecordingStudioStripe::BillingController.new

    assert_equal "focus", controller.recording_studio_resolved_layout
  end

  test "false turns the layout off" do
    @stripe.layout = false
    controller = RecordingStudioStripe::UsageController.new

    assert_equal false, controller.recording_studio_resolved_layout
  end

  test "a keyword callable receives the controller" do
    @stripe.layout = ->(controller:) { controller.class.name }
    plans = RecordingStudioStripe::PlansController.new
    admin = RecordingStudioStripe::Admin::ProductsController.new

    assert_equal "RecordingStudioStripe::PlansController", plans.recording_studio_resolved_layout
    assert_equal "RecordingStudioStripe::Admin::ProductsController", admin.recording_studio_resolved_layout
  end

  test "invalid layout values raise ArgumentError" do
    assert_raises(ArgumentError) { @stripe.layout = "" }
    assert_raises(ArgumentError) { @stripe.layout = :sidebar }
    assert_raises(ArgumentError) { @stripe.layout = ->(controller) { controller && "focus" } }
  end
end
