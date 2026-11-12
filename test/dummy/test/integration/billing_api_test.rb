# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class BillingApiTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  API_ROOT = "/recording_studio_api/api/v1"

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    Current.actor = @user
    @workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_owner_access!(recording: @root, actor: @user)
    @other = Workspace.find_or_create_by!(name: "Other Workspace")
    @other_root = RecordingStudio.root_recording_for(@other)
    grant_owner_access!(recording: @other_root, actor: @user)
    @admin_token = issue_token(role: :admin)
    @view_token = issue_token(role: :view)
  end

  teardown do
    Current.actor = nil
  end

  test "show billing is unauthorized without a token" do
    get "#{API_ROOT}/billing", as: :json

    assert_response :unauthorized
  end

  test "a view token can show billing and list plans" do
    get "#{API_ROOT}/billing", headers: auth(@view_token), as: :json
    assert_response :success
    body = response.parsed_body
    assert_equal @root.id, body.fetch("root_id")
    refute body.fetch("subscribed")

    get "#{API_ROOT}/billing/plans", headers: auth(@view_token), as: :json
    assert_response :success
    keys = response.parsed_body.fetch("groups").map { |group| group.fetch("key") }
    assert_includes keys, "studio"
    names = response.parsed_body.fetch("groups").flat_map { |group| group.fetch("products").map { |row| row.fetch("name") } }
    assert_includes names, "Pro"
  end

  test "a view token cannot write billing" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    post "#{API_ROOT}/billing/checkout",
         headers: auth(@view_token),
         params: checkout_params(price),
         as: :json
    assert_response :forbidden

    post "#{API_ROOT}/billing/change_plan",
         headers: auth(@view_token),
         params: { price_id: price.id },
         as: :json
    assert_response :forbidden

    post "#{API_ROOT}/billing/cancel", headers: auth(@view_token), as: :json
    assert_response :forbidden

    post "#{API_ROOT}/billing/resume", headers: auth(@view_token), as: :json
    assert_response :forbidden

    post "#{API_ROOT}/billing/keep_plan", headers: auth(@view_token), as: :json
    assert_response :forbidden

    post "#{API_ROOT}/billing/portal",
         headers: auth(@view_token),
         params: { return_url: "http://www.example.com/billing" },
         as: :json
    assert_response :forbidden
  end

  test "an admin token can checkout change cancel resume keep and open the portal" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    post "#{API_ROOT}/billing/checkout",
         headers: auth(@admin_token),
         params: checkout_params(starter),
         as: :json
    assert_response :success
    assert response.parsed_body.fetch("local")
    assert_equal "http://www.example.com/billing?checkout=ok", response.parsed_body.fetch("url")

    get "#{API_ROOT}/billing", headers: auth(@admin_token), as: :json
    assert_response :success
    assert response.parsed_body.fetch("subscribed")
    assert_equal @root.id, response.parsed_body.fetch("root_id")

    post "#{API_ROOT}/billing/change_plan",
         headers: auth(@admin_token),
         params: { price_id: pro.id },
         as: :json
    assert_response :success
    refute_equal starter.id, response.parsed_body.fetch("price_id")

    cheaper = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    post "#{API_ROOT}/billing/change_plan",
         headers: auth(@admin_token),
         params: { price_id: cheaper.id },
         as: :json
    assert_response :success
    assert_equal cheaper.id, response.parsed_body.fetch("scheduled_price_id")

    post "#{API_ROOT}/billing/keep_plan", headers: auth(@admin_token), as: :json
    assert_response :success
    assert_nil response.parsed_body.fetch("scheduled_price_id")

    post "#{API_ROOT}/billing/cancel", headers: auth(@admin_token), as: :json
    assert_response :success
    assert response.parsed_body.fetch("cancel_at_period_end")

    post "#{API_ROOT}/billing/resume", headers: auth(@admin_token), as: :json
    assert_response :success
    refute response.parsed_body.fetch("cancel_at_period_end")

    post "#{API_ROOT}/billing/portal",
         headers: auth(@admin_token),
         params: { return_url: "http://www.example.com/billing" },
         as: :json
    assert_response :success
    assert response.parsed_body.fetch("unavailable")
  end

  test "write endpoints are unauthorized without a token" do
    post "#{API_ROOT}/billing/checkout", params: checkout_params(nil), as: :json
    assert_response :unauthorized

    post "#{API_ROOT}/billing/portal", params: { return_url: "http://www.example.com/billing" }, as: :json
    assert_response :unauthorized
  end

  test "billing stays on the token workspace" do
    other_price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::StartCheckout.call(
      root_recording: @other_root,
      price: other_price,
      actor: @user,
      success_url: "http://www.example.com/billing?checkout=ok",
      cancel_url: "http://www.example.com/plans"
    )

    get "#{API_ROOT}/billing", headers: auth(@admin_token), as: :json
    assert_response :success
    assert_equal @root.id, response.parsed_body.fetch("root_id")
    refute response.parsed_body.fetch("subscribed")
  end

  test "checkout talks to the gem stripe test client not the network" do
    previous_key = RecordingStudioStripe.configuration.secret_key
    previous_client = RecordingStudioStripe.configuration.client
    client = RecordingStudioStripe::Testing::Client.new
    RecordingStudioStripe.configuration.secret_key = "sk_test_dummy"
    RecordingStudioStripe.configuration.client = client
    price = RecordingStudioStripe::Product.find_by!(name: "Inbox").monthly_price

    post "#{API_ROOT}/billing/checkout",
         headers: auth(@admin_token),
         params: checkout_params(price),
         as: :json

    assert_response :success
    assert_match %r{\Ahttps://checkout\.stripe\.test/}, response.parsed_body.fetch("url")
    assert_equal price.stripe_id, client.last_checkout_params.dig(:line_items, 0, :price)
  ensure
    RecordingStudioStripe.configuration.secret_key = previous_key
    RecordingStudioStripe.configuration.client = previous_client
  end

  private

  def issue_token(role:)
    original_manage = RecordingStudioAccessible.configuration.access_management_authorizer
    original_write = RecordingStudio.configuration.authorize_write
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    RecordingStudio.configuration.authorize_write = lambda { |actor:, root_recording:, recordable:, **|
      next true if actor.is_a?(RecordingStudioApi::ApiClient)

      original_write.call(actor: actor, root_recording: root_recording, recordable: recordable)
    }
    result = RecordingStudioAccessible::AccessCreationContext.allow do
      RecordingStudioApi::Services::IssueTestCredential.call(
        api: :public,
        actor: @user,
        access_point_recording: @root,
        role: role,
        name: "Stripe billing #{role} #{SecureRandom.hex(4)}"
      )
    end
    raise result.error unless result.success?

    result.value.fetch(:access_token)
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original_manage
    RecordingStudio.configuration.authorize_write = original_write
  end

  def auth(token)
    { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
  end

  def checkout_params(price)
    {
      price_id: price&.id,
      success_url: "http://www.example.com/billing?checkout=ok",
      cancel_url: "http://www.example.com/plans"
    }
  end
end
