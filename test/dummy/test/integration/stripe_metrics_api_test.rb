# frozen_string_literal: true

require "test_helper"

class StripeMetricsApiTest < ActionDispatch::IntegrationTest
  METRICS_INDEX = "/recording_studio_api/apis/operations/v1/metrics"
  PUBLIC_METRICS_INDEX = "/recording_studio_api/api/v1/metrics"

  setup do
    RecordingStudioStripe::Meter.sync_from_config!
    @staff = create_user("metrics-staff@example.com")
    @member = create_user("metrics-member@example.com")
    @admin_root = AdminRoot.find_or_create_by!(name: "Studio Admin")
    @admin_recording = RecordingStudio.root_recording_for(@admin_root)
    grant_owner_access!(recording: @admin_recording, actor: @staff)

    @workspace = Workspace.create!(name: "Metrics Workspace #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_owner_access!(recording: @root, actor: @member)

    seed_subscriptions_and_usage
    @staff_token = issue_token(access_point: @admin_recording, actor: @staff, api: :operations)
    @member_token = issue_token(access_point: @root, actor: @member, api: :operations)
    @public_token = issue_token(access_point: @root, actor: @member, api: :public)
  end

  test "metrics index lists stripe resources for staff operations tokens" do
    get METRICS_INDEX, headers: bearer_headers(@staff_token)

    assert_response :success
    identifiers = JSON.parse(response.body).fetch("metrics").map { |row| row.fetch("identifier") }
    expected = %w[
      stripe_subscriptions.active
      stripe_subscriptions.by_status
      stripe_subscriptions.by_plan
      stripe_subscriptions.new
      stripe_usage.total
      stripe_usage.over_time
    ]
    expected.each { |identifier| assert_includes identifiers, identifier }
  end

  test "active uses Subscription.current" do
    payload = fetch_metric("stripe_subscriptions", "active")

    assert_equal RecordingStudioStripe::Subscription.current.count, payload.fetch("value")
    assert_equal 3, payload.fetch("value")
  end

  test "by_status and by_plan break down seeded rows" do
    by_status = fetch_metric("stripe_subscriptions", "by_status").fetch("data").to_h { |row| [row.fetch("key").to_s, row.fetch("value")] }
    by_plan = fetch_metric("stripe_subscriptions", "by_plan").fetch("data").to_h { |row| [row.fetch("key").to_s, row.fetch("value")] }

    assert_equal 1, by_status["active"]
    assert_equal 1, by_status["trialing"]
    assert_equal 1, by_status["past_due"]
    assert_equal 1, by_status["canceled"]
    assert_equal 2, by_plan["studio"]
    assert_equal 2, by_plan["inbox"]
  end

  test "new timeseries counts created_at in the window" do
    payload = fetch_metric("stripe_subscriptions", "new", params: { interval: "month" })
    values = payload.fetch("data").to_h { |row| [row.fetch("date"), row.fetch("value")] }

    assert_equal 2, values["2026-03-01"]
    assert_equal 2, values["2026-04-01"]
  end

  test "usage total and over_time use quantity" do
    total = fetch_metric("stripe_usage", "total")
    assert_equal 15, total.fetch("value")

    series = fetch_metric("stripe_usage", "over_time", params: { interval: "month" })
    values = series.fetch("data").to_h { |row| [row.fetch("date"), row.fetch("value")] }

    assert_equal 5, values["2026-03-01"]
    assert_equal 10, values["2026-04-01"]
  end

  test "non-admin operations tokens and public tokens are denied" do
    get "#{METRICS_INDEX}/stripe_subscriptions/active", headers: bearer_headers(@member_token)
    assert_response :forbidden

    get METRICS_INDEX, headers: bearer_headers(@member_token)
    assert_response :success
    refute_includes JSON.parse(response.body).fetch("metrics").map { |row| row["identifier"] },
                    "stripe_subscriptions.active"

    get "#{METRICS_INDEX}/stripe_subscriptions/active", headers: bearer_headers(@public_token)
    assert_response :unauthorized

    get "#{PUBLIC_METRICS_INDEX}/stripe_subscriptions/active", headers: bearer_headers(@public_token)
    assert_includes [401, 403, 404], response.status
  end

  private

  def fetch_metric(resource, name, params: {})
    path = "#{METRICS_INDEX}/#{resource}/#{name}"
    path = "#{path}?#{params.to_query}" if params.present?
    get path, headers: bearer_headers(@staff_token)
    assert_response :success, response.body
    JSON.parse(response.body)
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_user(email)
    User.find_or_create_by!(email: email) do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
  end

  def seed_subscriptions_and_usage
    other = Workspace.create!(name: "Metrics Other #{SecureRandom.hex(4)}")
    other_root = RecordingStudio.root_recording_for(other)

    travel_to Time.utc(2026, 3, 10, 12) do
      create_subscription!(root: @root, status: "active", subscription_type: "studio")
      create_subscription!(root: @root, status: "canceled", subscription_type: "inbox")
    end
    travel_to Time.utc(2026, 4, 8, 12) do
      create_subscription!(root: other_root, status: "trialing", subscription_type: "studio")
      create_subscription!(root: other_root, status: "past_due", subscription_type: "inbox")
    end

    meter = RecordingStudioStripe::Meter.fetch("ai_tokens")
    travel_to Time.utc(2026, 3, 12, 12) do
      RecordingStudioStripe::UsageEntry.create!(
        meter: meter,
        root_recording_id: @root.id,
        quantity: 5,
        recorded_at: Time.current
      )
    end
    travel_to Time.utc(2026, 4, 12, 12) do
      RecordingStudioStripe::UsageEntry.create!(
        meter: meter,
        root_recording_id: other_root.id,
        quantity: 10,
        recorded_at: Time.current
      )
    end
  end

  def create_subscription!(root:, status:, subscription_type:)
    customer = RecordingStudioStripe::Customer.find_or_create_by!(root_recording_id: root.id) do |record|
      record.stripe_id = "cus_#{SecureRandom.hex(8)}"
    end
    RecordingStudioStripe::Subscription.create!(
      customer: customer,
      root_recording_id: root.id,
      stripe_id: "sub_#{SecureRandom.hex(8)}",
      status: status,
      subscription_type: subscription_type
    )
  end

  def issue_token(access_point:, actor:, api:)
    access = RecordingStudioAccessible.access_recordings_for_actor(
      recording: access_point,
      actor: actor
    ).first
    raise "missing access" unless access

    provision = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: access_point,
      manager_actor: actor,
      role: access.recordable.role,
      name: "#{api}-#{SecureRandom.hex(4)}",
      api: api
    )
    raise provision.error unless provision.success?

    payload = provision.value
    token = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: payload.fetch(:credential).oauth_client_id,
      client_secret: payload.fetch(:token),
      api: api
    )
    raise token.error unless token.success?

    token.value.fetch(:access_token)
  end
end
