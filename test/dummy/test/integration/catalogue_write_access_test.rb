# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class CatalogueWriteAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @admin_root = AdminRoot.find_or_create_by!(name: "Studio Admin")
    @admin_recording = RecordingStudio.create_root_recording!(@admin_root, actor: root_actor)
    grant_owner_access!(recording: @admin_recording, actor: @user)
    sign_in @user
    switch_to_root!(@admin_recording)
    @pro = RecordingStudioStripe::Product.find_by!(name: "Pro")
    @price = @pro.monthly_price
  end

  test "admin can write the catalogue and sees the write buttons" do
    get "/admin/screens/products"

    assert_response :success
    assert_includes response.body, "New Product"

    get "/admin/screens/products/table"

    assert_response :success
    assert_includes response.body, "Add Price"
    assert_match(%r{/admin/products/#{@pro.id}/edit}, response.body)
    assert_match(%r{/admin/prices/new\?product_id=}, response.body)

    get "/admin/screens/prices/table"

    assert_response :success
    assert_match(%r{/admin/prices/#{@price.id}/edit}, response.body)

    get "#{mount}/admin/products/new"

    assert_response :success
    assert_select "form[action*='admin/products'] button[type=submit]", text: "Create"

    assert_difference -> { RecordingStudioStripe::Product.count }, 1 do
      post "#{mount}/admin/products", params: {
        name: "Admin only #{SecureRandom.hex(4)}",
        kind: "plan",
        trial_days: "5",
        trial_unit_amount: "200"
      }
    end

    assert_response :redirect
  end

  test "a viewer can read the catalogue and cannot write it" do
    sign_in_with_role(:view)
    assert_catalogue_readable

    assert_no_difference -> { RecordingStudioStripe::Product.count } do
      post "#{mount}/admin/products", params: {
        name: "Viewer plan",
        kind: "plan",
        trial_days: "3",
        trial_unit_amount: "50"
      }
    end

    assert_response :forbidden
    assert_equal "Staff only.", response.body
    assert_nil RecordingStudioStripe::Product.find_by(name: "Viewer plan")
  end

  test "an editor can read the catalogue and is forbidden from every write" do
    sign_in_with_role(:edit)
    assert_catalogue_readable

    head "#{mount}/admin/products/new"

    assert_response :success

    product_count = RecordingStudioStripe::Product.count
    price_count = RecordingStudioStripe::Price.count
    included = @price.included_quantity("ai_tokens")

    assert_forbidden_write do
      post "#{mount}/admin/products", params: {
        name: "Editor plan",
        kind: "plan",
        trial_days: "9",
        trial_unit_amount: "75"
      }
    end
    assert_nil RecordingStudioStripe::Product.find_by(name: "Editor plan")
    assert_equal 14, @pro.reload.trial.days
    assert_equal 100, @pro.trial.unit_amount

    assert_forbidden_write do
      patch "#{mount}/admin/products/#{@pro.id}", params: {
        name: "Edited Pro",
        trial_days: "1",
        trial_unit_amount: "1"
      }
    end

    assert_forbidden_write do
      put "#{mount}/admin/products/#{@pro.id}", params: {
        name: "Put Pro",
        trial_days: "2",
        trial_unit_amount: "2"
      }
    end

    @pro.reload
    assert_equal "Pro", @pro.name
    assert_equal 14, @pro.trial.days
    assert_equal 100, @pro.trial.unit_amount

    assert_forbidden_write do
      post "#{mount}/admin/prices", params: {
        product_id: @pro.id,
        unit_amount: "4242",
        currency: "usd",
        interval: "month"
      }
    end

    assert_forbidden_write do
      patch "#{mount}/admin/prices/#{@price.id}", params: {
        included: { ai_tokens: "1" }
      }
    end

    assert_forbidden_write do
      put "#{mount}/admin/prices/#{@price.id}", params: {
        included: { ai_tokens: "2" }
      }
    end

    assert_equal product_count, RecordingStudioStripe::Product.count
    assert_equal price_count, RecordingStudioStripe::Price.count
    assert_equal included, @price.reload.included_quantity("ai_tokens")
    assert_equal "Staff only.", response.body
  end

  private

  def mount
    RecordingStudioStripe.configuration.mount_path
  end

  def sign_in_with_role(role)
    user = User.create!(
      email: "catalogue-#{role}-#{SecureRandom.hex(4)}@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    grant_owner_access!(recording: @admin_recording, actor: user, role: role)
    sign_out @user
    sign_in user
    switch_to_root!(@admin_recording)
    user
  end

  def assert_catalogue_readable
    get "/admin/screens/products"

    assert_response :success
    assert_includes response.body, "Products"
    refute_includes response.body, "New Product"

    get "/admin/screens/products/table"

    assert_response :success
    assert_includes response.body, "Pro"
    refute_includes response.body, "Add Price"
    refute_match(%r{/admin/products/[^"']+/edit}, response.body)
    refute_match(%r{/admin/prices/new}, response.body)

    get "/admin/screens/prices"

    assert_response :success
    assert_includes response.body, "Prices"

    get "/admin/screens/prices/table"

    assert_response :success
    assert_includes response.body, "month"
    refute_match(%r{/admin/prices/[^"']+/edit}, response.body)

    get "/admin/screens/credit_rates"

    assert_response :success
    assert_includes response.body, "Cents per credit"
    assert_includes response.body, "Before tax and coupons"

    get "/admin/screens/credit_rates/table"

    assert_response :success

    get "#{mount}/admin/products/new"

    assert_response :success
    assert_includes response.body, "New plan"
    assert_select "form[action*='admin/products'] button[type=submit]", count: 0

    get "#{mount}/admin/products/#{@pro.id}/edit"

    assert_response :success
    assert_includes response.body, "Edit Pro"
    assert_includes response.body, "Paid trial"
    assert_select "form[action*='admin/products'] button[type=submit]", count: 0

    get "#{mount}/admin/prices/new", params: { product_id: @pro.id }

    assert_response :success
    assert_includes response.body, "New Price"
    assert_select "form[action*='admin/prices'] button[type=submit]", count: 0

    get "#{mount}/admin/prices/#{@price.id}/edit"

    assert_response :success
    assert_includes response.body, "Edit Price"
    assert_select "form[action*='admin/prices'] button[type=submit]", count: 0
  end

  def assert_forbidden_write
    yield
    assert_response :forbidden
    assert_equal "Staff only.", response.body
  end
end
