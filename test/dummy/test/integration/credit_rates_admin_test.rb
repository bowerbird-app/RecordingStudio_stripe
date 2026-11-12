# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class CreditRatesAdminTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @admin_root = AdminRoot.find_or_create_by!(name: "Studio Admin")
    @admin_recording = RecordingStudio.root_recording_for(@admin_root)
    grant_owner_access!(recording: @admin_recording, actor: @user)
    sign_in @user
    switch_to_root!(@admin_recording)
    @suffix = SecureRandom.hex(4)
    @cheap = pack(name: "Cheap pack #{@suffix}", unit_amount: 200, allowance: 1_000)
    @dear = plan(name: "Dear plan #{@suffix}", unit_amount: 9_000, credits: 100)
    plan(name: "Trial fee #{@suffix}", unit_amount: 100, credits: nil,
         metadata: { "kind" => "trial_fee", "meter" => "credits", "allowance" => "100" }, kind: "allowance")
  end

  test "staff with admin access see cents per credit and the cheapest price" do
    get "/admin"

    assert_response :success
    assert_includes response.body, "Cents per credit"

    get "/admin/screens/credit_rates"

    assert_response :success
    assert_includes response.body, "Before tax and coupons"
    assert_includes response.body, "A plan price assumes the whole price is for credits."

    get "/admin/screens/credit_rates/table"

    assert_response :success
    assert_includes response.body, @cheap.name
    assert_includes response.body, @dear.name
    assert_includes response.body, "Cheapest"
    assert_includes response.body, "Assumes the whole price is for credits."
    refute_includes response.body, "Trial fee #{@suffix}"
  end

  test "staff without admin access cannot open cents per credit" do
    outsider = User.create!(email: "credit-rates-#{SecureRandom.hex(4)}@example.com", password: "Password",
                            password_confirmation: "Password")
    sign_out @user
    sign_in outsider

    get "/admin/screens/credit_rates"

    assert_response :forbidden
  end

  private

  def plan(name:, unit_amount:, credits:, metadata: nil, kind: "plan")
    product = RecordingStudioStripe::Product.create!(
      stripe_id: "prod_#{SecureRandom.hex(6)}",
      name: name,
      kind: kind,
      subscription_type: "studio"
    )
    data = metadata || { "included_credits" => credits.to_s }
    RecordingStudioStripe::Price.create!(
      stripe_id: "price_#{SecureRandom.hex(6)}",
      product: product,
      unit_amount: unit_amount,
      currency: "usd",
      interval: kind == "plan" ? "month" : nil,
      metadata: data
    )
    product
  end

  def pack(name:, unit_amount:, allowance:)
    plan(name: name, unit_amount: unit_amount, credits: nil, kind: "allowance",
         metadata: { "meter" => "credits", "allowance" => allowance.to_s })
  end
end
