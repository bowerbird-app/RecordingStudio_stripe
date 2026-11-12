# frozen_string_literal: true

require "test_helper"

class ApiTest < Minitest::Test
  def test_register_is_a_noop_without_recording_studio_api
    refute Object.const_defined?(:RecordingStudioApi, false)
    assert_nil RecordingStudioStripe::Api.register!
  end

  def test_availability_is_one_check
    api = File.read(File.expand_path("../lib/recording_studio_stripe/api.rb", __dir__))
    registration = File.read(File.expand_path("../lib/recording_studio_stripe/api/registration.rb", __dir__))
    engine = File.read(File.expand_path("../lib/recording_studio_stripe/engine.rb", __dir__))

    assert_includes api, "def self.available?"
    assert_includes api, "defined?(RecordingStudioApi) && RecordingStudioApi.respond_to?(:register_endpoint)"
    assert_includes api, "return unless available?"
    refute_includes registration, "defined?(RecordingStudioApi)"
    refute_includes registration, "respond_to?(:register_endpoint)"
    assert_includes engine, 'initializer "recording_studio_stripe.api"'
    assert_includes engine, "RecordingStudioStripe::Api.register!"
  end

  def test_endpoints_match_html_roles
    expected = {
      show_billing: :view,
      list_plans: :view,
      start_checkout: :admin,
      change_plan: :admin,
      cancel_subscription: :admin,
      resume_subscription: :admin,
      keep_plan: :admin,
      start_portal: :admin
    }

    roles = RecordingStudioStripe::Api::Registration::ENDPOINTS.to_h do |endpoint|
      [endpoint.fetch(:name), endpoint.fetch(:role)]
    end

    assert_equal expected, roles
  end

  def test_handlers_authorize_then_call_existing_methods
    handlers = File.read(File.expand_path("../lib/recording_studio_stripe/api/handlers.rb", __dir__))

    assert_includes handlers, "Authorize.call(context, :view)"
    assert_includes handlers, "Authorize.call(context, :admin)"
    assert_includes handlers, "Billing.for(context.root_recording.recordable)"
    assert_includes handlers, "Catalog.plan_groups"
    assert_includes handlers, "RecordingStudioStripe::StartCheckout.call"
    assert_includes handlers, "RecordingStudioStripe::ChangePlan.call"
    assert_includes handlers, "RecordingStudioStripe::CancelSubscription.call"
    assert_includes handlers, "RecordingStudioStripe::ResumeSubscription.call"
    assert_includes handlers, "RecordingStudioStripe::ClearScheduledChange.call"
    assert_includes handlers, "RecordingStudioStripe::StartPortalSession.call"
    assert_includes handlers, "context.access_grant.actor"
    refute_includes handlers, "const_set"
    refute_includes handlers, "remove_const"
    refute_includes handlers, "map_to_api_error"
    assert_includes handlers, 'Copy.t("alerts.portal_needs_pay")'
    assert_includes handlers, 'Copy.t("alerts.portal_failed")'
    refute_includes handlers, "NoCustomer, Stripe::StripeError"
  end

  def test_billing_json_omits_customer_ids
    serialize = File.read(File.expand_path("../lib/recording_studio_stripe/api/serialize.rb", __dir__))

    refute_includes serialize, "customer_id"
    refute_includes serialize, "stripe_customer_id"
  end

  def test_openapi_summaries_are_not_titles
    RecordingStudioStripe::Api::Registration::ENDPOINTS.each do |endpoint|
      refute_equal endpoint.fetch(:title), endpoint.fetch(:summary)
      assert_match(/\A[A-Z].+\.\z/, endpoint.fetch(:summary))
    end
  end

  def test_gemspec_keeps_api_off_the_runtime
    gemspec = File.read(File.expand_path("../recording_studio_stripe.gemspec", __dir__))

    refute_includes gemspec, "recording_studio_api"
  end
end
