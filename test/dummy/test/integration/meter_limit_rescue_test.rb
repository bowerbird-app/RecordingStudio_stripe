# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class MeterLimitRescueTest < ActionDispatch::IntegrationTest
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

  test "html meter limit redirects to usage" do
    controller = ApplicationController.new
    controller.set_request!(ActionDispatch::TestRequest.create)
    controller.set_response!(ActionDispatch::TestResponse.new)
    error = RecordingStudioStripe::MeterLimitReached.new(handle: @workspace.billing.meter(:ai_tokens))

    controller.send(:recording_studio_stripe_meter_limit_reached, error)

    assert_equal 302, controller.response.status
    assert_equal "/billing/usage", URI.parse(controller.response.redirect_url).path
    assert_includes controller.flash[:alert], "ai tokens"
  end

  test "json meter limit is forbidden" do
    request = ActionDispatch::TestRequest.create
    request.set_header("HTTP_ACCEPT", "application/json")
    controller = ApplicationController.new
    controller.set_request!(request)
    controller.set_response!(ActionDispatch::TestResponse.new)
    error = RecordingStudioStripe::MeterLimitReached.new(handle: @workspace.billing.meter(:ai_tokens))

    controller.send(:recording_studio_stripe_meter_limit_reached, error)

    assert_equal 403, controller.response.status
    body = JSON.parse(controller.response.body)
    assert_equal "meter_limit_reached", body.fetch("code")
    assert_includes body.fetch("message"), "ai tokens"
  end
end
