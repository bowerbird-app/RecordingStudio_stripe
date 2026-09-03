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
    switch_to_root!(@admin_recording)
  end

  test "admin stripe section lists Products and past due" do
    get "/admin"

    assert_response :success
    assert_includes response.body, "Stripe"
    assert_includes response.body, "Products"
    assert_includes response.body, "Past due"
    assert_includes response.body, "Active subscriptions"
    assert_includes response.body, "Paywalls"
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
    assert_includes response.body, "Inbox"
    assert_includes response.body, "Opens"
    assert_includes response.body, "Generate an image"
    assert_includes response.body, "Edit"
  end

  test "paywalls screen lists registered names" do
    get "/admin/screens/paywalls"

    assert_response :success
    assert_includes response.body, "Paywalls"
    assert_includes response.body, "New paywall"

    get "/admin/screens/paywalls/table"

    assert_response :success
    assert_includes response.body, "generate_image"
    assert_includes response.body, "Generate an image"
    assert_includes response.body, "export_csv"
  end

  test "staff can create a paywall from the engine form" do
    get RecordingStudioStripe.configuration.mount_path + "/admin/paywalls/new"

    assert_response :success
    assert_includes response.body, "New paywall"

    assert_difference -> { RecordingStudioStripe::Paywall.count }, 1 do
      post RecordingStudioStripe.configuration.mount_path + "/admin/paywalls", params: {
        name: "share_link",
        label: "Share a link"
      }
    end

    follow_redirect!
    assert RecordingStudioStripe::Paywall.exists?(name: "share_link")
  end

  test "staff can create a Product from the engine form" do
    get RecordingStudioStripe.configuration.mount_path + "/admin/products/new"

    assert_response :success
    assert_includes response.body, "What this plan opens"
    assert_includes response.body, "Generate an image"
    assert_includes response.body, "Plan group"

    assert_difference -> { RecordingStudioStripe::Product.count }, 1 do
      post RecordingStudioStripe.configuration.mount_path + "/admin/products", params: {
        name: "Studio",
        kind: "plan",
        description: "For people who ship every week.",
        paywall_names: %w[generate_image export_csv]
      }
    end

    follow_redirect!
    assert_includes response.body, "Studio"
    product = RecordingStudioStripe::Product.find_by!(name: "Studio")
    assert_equal "studio", product.subscription_type
    assert_equal %w[export_csv generate_image], product.paywalls.order(:name).pluck(:name)
  end

  test "staff can edit a Product and tick paywalls" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter")
    get RecordingStudioStripe.configuration.mount_path + "/admin/products/#{starter.id}/edit"

    assert_response :success
    assert_includes response.body, "What this plan opens"

    patch RecordingStudioStripe.configuration.mount_path + "/admin/products/#{starter.id}", params: {
      name: "Starter",
      description: starter.description,
      paywall_names: %w[export_csv]
    }

    follow_redirect!
    assert_equal %w[export_csv], starter.reload.paywalls.order(:name).pluck(:name)
  end

  test "allowance Products ignore paywall ticks" do
    assert_difference -> { RecordingStudioStripe::Product.count }, 1 do
      post RecordingStudioStripe.configuration.mount_path + "/admin/products", params: {
        name: "Extra seats",
        kind: "allowance",
        description: "One-time seats.",
        paywall_names: %w[generate_image]
      }
    end

    product = RecordingStudioStripe::Product.find_by!(name: "Extra seats")
    assert_predicate product, :allowance?
    assert_empty product.paywalls
  end

  test "prices screen groups Prices under their Product" do
    get "/admin/screens/prices"

    assert_response :success
    assert_includes response.body, "Prices"
    assert_includes response.body, "Product"
    assert_includes response.body, "Interval"

    get "/admin/screens/prices/table"

    assert_response :success
    assert_includes response.body, "Starter"
    assert_includes response.body, "Pro"
    assert_includes response.body, "month"
    assert_includes response.body, "year"

    get "/admin/screens/prices/table", params: { product: "Starter" }

    assert_response :success
    assert_includes response.body, "Starter"
    refute_includes response.body, ">Pro<"
  end
end
