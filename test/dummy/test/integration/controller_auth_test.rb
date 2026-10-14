# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class ControllerAuthTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_owner_access!(recording: @root, actor: @user, role: :admin)
  end

  test "billing application controller includes ControllerAuth with stripe-shaped options" do
    controller = RecordingStudioStripe::ApplicationController
    options = controller.recording_studio_auth_options

    assert controller.included_modules.include?(RecordingStudioAccessible::ControllerAuth)
    assert_equal false, options[:authenticate]
    assert_equal false, options[:set_current_actor]
    assert_equal true, options[:require_actor]
    assert_equal :current_actor, options[:actor_method]
    assert_equal :current_billing_root, options[:root_method]
    assert_equal :not_found, options[:missing_root_status]
    assert controller.private_method_defined?(:current_actor)
    assert controller.private_method_defined?(:current_billing_root)
    assert controller.private_method_defined?(:require_root_recording!)
    refute_includes controller.action_methods, "current_actor"
    refute_includes controller.action_methods, "current_billing_root"
  end

  test "signed-out plans visit redirects to sign in" do
    get "/plans"

    assert_redirected_to new_user_session_path
  end

  test "signed-in actor without a billing root gets plain not_found" do
    sign_in @user
    previous = RecordingStudioStripe.configuration.current_root_recording
    RecordingStudioStripe.configuration.current_root_recording = -> { nil }

    get "/plans"

    assert_response :not_found
    assert_equal RecordingStudioStripe::Copy.t("alerts.pick_workspace"), response.body
  ensure
    RecordingStudioStripe.configuration.current_root_recording = previous
  end

  test "view role can read plans and is forbidden from checkout" do
    viewer = User.find_or_create_by!(email: "viewer-auth@example.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    grant_owner_access!(recording: @root, actor: viewer, role: :view)
    sign_in viewer
    switch_to_root!(@root)

    get "/plans"

    assert_response :success
    assert_includes response.body, "Pricing"

    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    post recording_studio_stripe.checkout_path, params: { price_id: price.id }

    assert_response :forbidden
    assert_equal RecordingStudioStripe::Copy.t("alerts.no_access"), response.body
    refute @workspace.billing.subscribed?
  end

  test "admin role reaches checkout authorize path" do
    sign_in @user
    switch_to_root!(@root)

    get "/billing"

    assert_response :success

    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    post recording_studio_stripe.checkout_path, params: { price_id: price.id }

    assert_response :redirect
  end

  test "config.current_actor and config.current_root_recording still drive resolvers" do
    other = User.find_or_create_by!(email: "resolver-auth@example.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    root = @root
    grant_owner_access!(recording: root, actor: other, role: :view)
    sign_in @user
    switch_to_root!(root)

    previous_actor = RecordingStudioStripe.configuration.current_actor
    previous_root = RecordingStudioStripe.configuration.current_root_recording
    RecordingStudioStripe.configuration.current_actor = -> { other }
    RecordingStudioStripe.configuration.current_root_recording = -> { root }

    get "/plans"

    assert_response :success
  ensure
    RecordingStudioStripe.configuration.current_actor = previous_actor
    RecordingStudioStripe.configuration.current_root_recording = previous_root
  end

  test "config.authenticate is ignored when Accessible is loaded" do
    sign_in @user
    switch_to_root!(@root)
    previous = RecordingStudioStripe.configuration.authenticate
    called = false
    RecordingStudioStripe.configuration.authenticate = lambda {
      called = true
      false
    }

    get "/plans"

    assert_response :success
    refute called, "Accessible path must win; authenticate must not run"
  ensure
    RecordingStudioStripe.configuration.authenticate = previous
  end

  test "config.authenticate allows and denies when Accessible is absent" do
    sign_in @user
    switch_to_root!(@root)
    accessible = ::RecordingStudioAccessible
    Object.send(:remove_const, :RecordingStudioAccessible)
    previous = RecordingStudioStripe.configuration.authenticate
    no_access = RecordingStudioStripe::Copy.t("alerts.no_access")

    RecordingStudioStripe.configuration.authenticate = -> { true }
    get "/plans"
    assert_response :success

    RecordingStudioStripe.configuration.authenticate = -> { false }
    get "/billing"
    assert_response :forbidden
    assert_equal no_access, response.body

    RecordingStudioStripe.configuration.authenticate = nil
    get "/billing"
    assert_response :forbidden
    assert_equal no_access, response.body
  ensure
    unless defined?(::RecordingStudioAccessible)
      Object.const_set(:RecordingStudioAccessible, accessible)
    end
    RecordingStudioStripe.configuration.authenticate = previous
  end
end


