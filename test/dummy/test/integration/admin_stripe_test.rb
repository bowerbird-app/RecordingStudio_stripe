# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class AdminStripeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @admin_root = AdminRoot.find_or_create_by!(name: "Studio Admin")
    @admin_recording = RecordingStudio.root_recording_for(@admin_root)
    grant_owner_access!(recording: @admin_recording, actor: @user)
    sign_in @user
  end

  test "admin stripe section lists Products and past due" do
    get "/admin"

    assert_response :success
    assert_includes response.body, "Stripe"
    assert_includes response.body, "Products"
    assert_includes response.body, "Past due"
    assert_includes response.body, "Active subscriptions"
  end

  test "products screen lists the demo catalogue" do
    get "/admin/screens/products"

    assert_response :success
    assert_includes response.body, "Products"
    assert_includes response.body, "New Product"

    get "/admin/screens/products/table"

    assert_response :success
    assert_includes response.body, "Pro"
    assert_includes response.body, "Starter"
  end

  test "staff can create a Product from the engine form" do
    get RecordingStudioStripe.configuration.mount_path + "/admin/products/new"

    assert_response :success

    assert_difference -> { RecordingStudioStripe::Product.count }, 1 do
      post RecordingStudioStripe.configuration.mount_path + "/admin/products", params: {
        name: "Studio",
        kind: "plan",
        description: "For people who ship every week."
      }
    end

    follow_redirect!
    assert_includes response.body, "Studio"
  end
end
