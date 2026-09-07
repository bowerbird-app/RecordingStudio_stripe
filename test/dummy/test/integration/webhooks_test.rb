# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class WebhooksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    @root = RecordingStudio.root_recording_for(@workspace)
  end

  test "checkout.session.completed grants an allowance pack" do
    price = RecordingStudioStripe::Price.one_time.find_by!("metadata ->> 'allowance' = '5000000'")

    post "/webhooks/stripe",
         params: stripe_event(
           "evt_allowance_1",
           "checkout.session.completed",
           {
             "id" => "cs_test_allowance",
             "mode" => "payment",
             "client_reference_id" => @root.id.to_s,
             "metadata" => {
               "root_recording_id" => @root.id.to_s,
               "price_id" => price.stripe_id
             }
           }
         ),
         as: :json

    assert_response :success
    meter = @workspace.billing.meter(:ai_tokens)
    assert_equal 5_000_000, meter.purchased
  end

  test "customer.subscription.created projects the Subscription" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    post "/webhooks/stripe",
         params: stripe_event(
           "evt_sub_1",
           "customer.subscription.created",
           {
             "id" => "sub_test_pro",
             "customer" => "cus_test_pro",
             "status" => "active",
             "cancel_at_period_end" => false,
             "metadata" => { "root_recording_id" => @root.id.to_s },
             "items" => {
               "data" => [
                 {
                   "id" => "si_test_pro",
                   "price" => { "id" => price.stripe_id },
                   "current_period_start" => 1.day.ago.to_i,
                   "current_period_end" => 29.days.from_now.to_i
                 }
               ]
             }
           }
         ),
         as: :json

    assert_response :success
    subscription = @workspace.billing.subscription
    assert_predicate subscription, :active?
    assert_equal price.id, subscription.price_id
    assert_equal "si_test_pro", subscription.metadata["stripe_item_id"]
  end

  test "duplicate Stripe event ids are ignored" do
    price = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    payload = stripe_event(
      "evt_dup_1",
      "customer.subscription.created",
      {
        "id" => "sub_dup",
        "customer" => "cus_dup",
        "status" => "active",
        "cancel_at_period_end" => false,
        "metadata" => { "root_recording_id" => @root.id.to_s },
        "items" => { "data" => [{ "id" => "si_dup", "price" => { "id" => price.stripe_id } }] }
      }
    )

    post "/webhooks/stripe", params: payload, as: :json
    post "/webhooks/stripe", params: payload, as: :json

    assert_response :success
    assert_equal 1, RecordingStudioStripe::WebhookEvent.where(stripe_id: "evt_dup_1").count
  end

  test "checkout.session.completed fulfils a subscription" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    post "/webhooks/stripe",
         params: stripe_event(
           "evt_checkout_sub_1",
           "checkout.session.completed",
           {
             "id" => "cs_test_sub",
             "mode" => "subscription",
             "subscription" => "sub_from_checkout",
             "customer" => "cus_from_checkout",
             "client_reference_id" => @root.id.to_s,
             "metadata" => {
               "root_recording_id" => @root.id.to_s,
               "price_id" => price.stripe_id
             }
           }
         ),
         as: :json

    assert_response :success
    subscription = @workspace.billing.subscription
    assert_predicate subscription, :active?
    assert_equal price.id, subscription.price_id
    assert_equal "sub_from_checkout", subscription.stripe_id
  end

  test "checkout fulfilment keeps existing period dates" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    period_start = Time.zone.at(1_700_000_000)
    period_end = Time.zone.at(1_702_592_000)

    post "/webhooks/stripe",
         params: stripe_event(
           "evt_sub_periods",
           "customer.subscription.created",
           {
             "id" => "sub_keep_periods",
             "customer" => "cus_keep_periods",
             "status" => "active",
             "cancel_at_period_end" => false,
             "metadata" => { "root_recording_id" => @root.id.to_s },
             "items" => {
               "data" => [
                 {
                   "id" => "si_keep_periods",
                   "price" => { "id" => price.stripe_id },
                   "current_period_start" => period_start.to_i,
                   "current_period_end" => period_end.to_i
                 }
               ]
             }
           }
         ),
         as: :json

    post "/webhooks/stripe",
         params: stripe_event(
           "evt_checkout_keep_periods",
           "checkout.session.completed",
           {
             "id" => "cs_keep_periods",
             "mode" => "subscription",
             "subscription" => "sub_keep_periods",
             "customer" => "cus_keep_periods",
             "client_reference_id" => @root.id.to_s,
             "metadata" => {
               "root_recording_id" => @root.id.to_s,
               "price_id" => price.stripe_id
             }
           }
         ),
         as: :json

    assert_response :success
    subscription = @workspace.billing.subscription
    assert_equal period_start, subscription.current_period_start
    assert_equal period_end, subscription.current_period_end
  end

  test "unknown price is not stored so Stripe can retry" do
    post "/webhooks/stripe",
         params: stripe_event(
           "evt_missing_price",
           "customer.subscription.created",
           {
             "id" => "sub_missing_price",
             "customer" => "cus_missing",
             "status" => "active",
             "metadata" => { "root_recording_id" => @root.id.to_s },
             "items" => { "data" => [{ "id" => "si_missing", "price" => { "id" => "price_unknown" } }] }
           }
         ),
         as: :json

    assert_response :service_unavailable
    refute RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_missing_price")
  end

  test "invoice.payment_failed marks past_due and invoice.paid clears it" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: price,
      stripe_subscription_id: "sub_invoice",
      stripe_customer_id: "cus_invoice"
    )

    post "/webhooks/stripe",
         params: stripe_event(
           "evt_fail_1",
           "invoice.payment_failed",
           {
             "id" => "in_fail",
             "parent" => {
               "type" => "subscription_details",
               "subscription_details" => { "subscription" => "sub_invoice" }
             }
           }
         ),
         as: :json

    assert_response :success
    assert_equal "past_due", @workspace.billing.subscription.status

    post "/webhooks/stripe",
         params: stripe_event(
           "evt_paid_1",
           "invoice.paid",
           {
             "id" => "in_paid",
             "paid" => true,
             "parent" => {
               "type" => "subscription_details",
               "subscription_details" => { "subscription" => "sub_invoice" }
             }
           }
         ),
         as: :json

    assert_response :success
    assert_equal "active", @workspace.billing.subscription.reload.status
  end

  test "invoice events still read a legacy subscription field" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: price,
      stripe_subscription_id: "sub_legacy_invoice",
      stripe_customer_id: "cus_legacy_invoice"
    )

    post "/webhooks/stripe",
         params: stripe_event(
           "evt_legacy_fail",
           "invoice.payment_failed",
           { "id" => "in_legacy", "subscription" => "sub_legacy_invoice" }
         ),
         as: :json

    assert_response :success
    assert_equal "past_due", @workspace.billing.subscription.reload.status
  end

  test "configured Stripe without a webhook secret rejects unsigned events" do
    previous_client = RecordingStudioStripe.configuration.client
    RecordingStudioStripe.configuration.client = RecordingStudioStripe::Testing::Client.new

    post "/webhooks/stripe",
         params: stripe_event("evt_unsigned", "customer.subscription.created", { "id" => "sub_unsigned" }),
         as: :json

    assert_response :bad_request
    refute RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_unsigned")
  ensure
    RecordingStudioStripe.configuration.client = previous_client
  end

  private

  def stripe_event(id, type, object)
    { "id" => id, "object" => "event", "type" => type, "data" => { "object" => object } }
  end
end
