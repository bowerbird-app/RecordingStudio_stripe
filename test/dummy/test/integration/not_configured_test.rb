# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"
require "minitest/mock"

class NotConfiguredTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    @root = RecordingStudio.create_root_recording!(@workspace, actor: root_actor)
    grant_owner_access!(recording: @root, actor: @user)
    sign_in @user
    switch_to_root!(@root)
    @pack = RecordingStudioStripe::Price.one_time.find_by!("metadata ->> 'allowance' = '5000000'")
    @configuration = RecordingStudioStripe.configuration
    @previous = {
      secret_key: @configuration.secret_key,
      client: @configuration.client
    }
    @configuration.secret_key = nil
    @configuration.client = nil
  end

  teardown do
    @configuration.secret_key = @previous[:secret_key]
    @configuration.client = @previous[:client]
  end

  test "html checkout without a stripe key returns the not configured page" do
    in_production do
      post recording_studio_stripe.allowances_path, params: { price_id: @pack.id }
    end

    assert_response :service_unavailable
    assert_includes response.body, "Checkout and the portal stay off until Stripe keys are set."
    assert_select "h3", text: "Billing isn’t set up"
  end

  test "json checkout without a stripe key returns service unavailable" do
    in_production do
      post recording_studio_stripe.allowances_path, params: { price_id: @pack.id }, as: :json
    end

    assert_response :service_unavailable
    assert_equal "application/json", response.media_type
    assert_equal "Billing isn’t set up", response.parsed_body.fetch("error")
  end

  private

  def in_production(&)
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production"), &)
  end
end
