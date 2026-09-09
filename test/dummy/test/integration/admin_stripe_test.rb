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
    assert_includes response.body, "Team"
    assert_includes response.body, "Inbox Pro"
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
    assert_includes response.body, "How many they can keep"
    assert_includes response.body, "Press kits"
    assert_includes response.body, "On the plan card"
    assert_includes response.body, "Hide from the card"

    assert_difference -> { RecordingStudioStripe::Product.count }, 1 do
      post RecordingStudioStripe.configuration.mount_path + "/admin/products", params: {
        name: "Studio",
        kind: "plan",
        description: "For people who ship every week.",
        paywall_names: %w[generate_image export_csv],
        limits: { press_kits: 4 },
        plan_card: {
          hide: [ "meter:api_calls" ],
          order: "limit:press_kits\nmeter:ai_tokens\npaywall:generate_image\nextra:priority",
          extras: {
            "0" => { key: "priority", text: "Someone picks up the phone", icon: "phone" }
          }
        }
      }
    end

    follow_redirect!
    assert_includes response.body, "Studio"
    product = RecordingStudioStripe::Product.find_by!(name: "Studio")
    assert_equal "studio", product.subscription_type
    assert_equal %w[export_csv generate_image], product.paywalls.order(:name).pluck(:name)
    assert_equal 4, product.limit_quantity("press_kits")
    card = product.plan_card_settings
    assert_equal [ "meter:api_calls" ], card["hide"]
    assert_equal %w[limit:press_kits meter:ai_tokens paywall:generate_image extra:priority], card["order"]
    assert_equal "Someone picks up the phone", card["extras"].first["text"]
    assert_equal "phone", card["extras"].first["icon"]
  end

  test "staff can edit a Product and tick paywalls" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter")
    get RecordingStudioStripe.configuration.mount_path + "/admin/products/#{starter.id}/edit"

    assert_response :success
    assert_includes response.body, "What this plan opens"
    assert_includes response.body, "On the plan card"
    assert_includes response.body, "Hide from the card"

    patch RecordingStudioStripe.configuration.mount_path + "/admin/products/#{starter.id}", params: {
      name: "Starter",
      description: starter.description,
      paywall_names: %w[export_csv],
      limits: { press_kits: 5 },
      plan_card: {
        hide: [ "meter:api_calls" ],
        extras: {
          "0" => { key: "human", text: "A human answers when you ring", icon: "phone" }
        }
      }
    }

    follow_redirect!
    assert_equal %w[export_csv], starter.reload.paywalls.order(:name).pluck(:name)
    assert_equal 5, starter.limit_quantity("press_kits")
    assert_equal [ "meter:api_calls" ], starter.plan_card_settings["hide"]
    assert_equal "A human answers when you ring", starter.plan_card_settings["extras"].first["text"]
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

  test "staff can edit included usage on a Price" do
    price = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    get RecordingStudioStripe.configuration.mount_path + "/admin/prices/#{price.id}/edit"

    assert_response :success
    assert_includes response.body, "Included ai tokens"

    patch RecordingStudioStripe.configuration.mount_path + "/admin/prices/#{price.id}", params: {
      included: { ai_tokens: "2500000", api_calls: "20000" }
    }

    follow_redirect!
    price.reload
    assert_equal 2_500_000, price.included_quantity("ai_tokens")
    assert_equal 20_000, price.included_quantity("api_calls")
  end

  test "staff can create a Price from the engine form" do
    product = RecordingStudioStripe::Product.find_by!(name: "Starter")
    get RecordingStudioStripe.configuration.mount_path + "/admin/prices/new", params: { product_id: product.id }

    assert_response :success
    assert_includes response.body, "Amount in cents"

    assert_difference -> { RecordingStudioStripe::Price.count }, 1 do
      post RecordingStudioStripe.configuration.mount_path + "/admin/prices", params: {
        product_id: product.id,
        unit_amount: "1500",
        currency: "usd",
        interval: "month",
        included: { ai_tokens: "1000", api_calls: "10" }
      }
    end

    price = RecordingStudioStripe::Price.order(:created_at).last
    assert_equal 1500, price.unit_amount
    assert_equal "month", price.interval
    assert_equal 1000, price.included_quantity("ai_tokens")
  end

  test "staff can create a meter from the engine form" do
    get RecordingStudioStripe.configuration.mount_path + "/admin/meters/new"

    assert_response :success
    assert_includes response.body, "New meter"

    assert_difference -> { RecordingStudioStripe::Meter.count }, 1 do
      post RecordingStudioStripe.configuration.mount_path + "/admin/meters", params: {
        name: "seats",
        label: "Seats"
      }
    end

    assert RecordingStudioStripe::Meter.exists?(name: "seats")
  end

  test "blank included usage clears the old amount" do
    price = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    patch RecordingStudioStripe.configuration.mount_path + "/admin/prices/#{price.id}", params: {
      included: { ai_tokens: "", api_calls: "20000" }
    }

    price.reload
    assert_equal 0, price.included_quantity("ai_tokens")
    assert_equal 20_000, price.included_quantity("api_calls")
  end
end
