# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"
require "minitest/mock"

class WebhooksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    @root = RecordingStudio.create_root_recording!(@workspace, actor: root_actor)
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
             "payment_status" => "paid",
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
             "payment_status" => "paid",
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
             "payment_status" => "paid",
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

  test "configured Stripe without a webhook secret returns service unavailable" do
    previous_client = RecordingStudioStripe.configuration.client
    RecordingStudioStripe.configuration.client = RecordingStudioStripe::Testing::Client.new
    errors = []

    Rails.logger.stub(:error, ->(message = nil, &block) { errors << (message || block&.call) }) do
      post "/webhooks/stripe",
           params: stripe_event("evt_unsigned", "customer.subscription.created", { "id" => "sub_unsigned" }),
           as: :json
    end

    assert_response :service_unavailable
    refute RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_unsigned")
    assert_includes errors.compact.join, "STRIPE_WEBHOOK_SECRET missing"
  ensure
    RecordingStudioStripe.configuration.client = previous_client
  end

  test "unsigned events are rejected in production" do
    with_webhook_settings(secret_key: nil, client: nil, webhook_secret: nil) do
      Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
        refute_predicate RecordingStudioStripe.configuration, :local_mode?
        post "/webhooks/stripe",
             params: "{not-json",
             headers: { "CONTENT_TYPE" => "application/json" }
        assert_response :service_unavailable
        post_unsigned("evt_unsigned_production")
      end
    end

    assert_response :service_unavailable
    refute RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_unsigned_production")
  end

  test "a bad signature is rejected" do
    with_webhook_settings(webhook_secret: "whsec_test_fixture") do
      payload = unsigned_body("evt_bad_signature")
      post "/webhooks/stripe",
           params: payload,
           headers: {
             "CONTENT_TYPE" => "application/json",
             "HTTP_STRIPE_SIGNATURE" => "t=#{Time.now.to_i},v1=deadbeef"
           }
    end

    assert_response :bad_request
    refute RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_bad_signature")
  end

  test "a valid signature is accepted" do
    secret = "whsec_test_fixture"
    payload = unsigned_body("evt_signed_ok")
    signature = signed_header(payload, secret)

    with_webhook_settings(webhook_secret: secret) do
      post "/webhooks/stripe",
           params: payload,
           headers: { "CONTENT_TYPE" => "application/json", "HTTP_STRIPE_SIGNATURE" => signature }
    end

    assert_response :success
    assert RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_signed_ok")
  end

  test "unsigned events are allowed in development and test local mode" do
    %w[development test].each do |name|
      event_id = "evt_unsigned_#{name}"
      with_webhook_settings(secret_key: nil, client: nil, webhook_secret: nil) do
        Rails.stub(:env, ActiveSupport::StringInquirer.new(name)) do
          assert_predicate RecordingStudioStripe.configuration, :local_mode?
          post_unsigned(event_id)
        end
      end

      assert_response :success
      assert RecordingStudioStripe::WebhookEvent.exists?(stripe_id: event_id)
    end
  end

  test "a resent checkout does not restore an older plan" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    secret = "whsec_replay_order"
    client = CheckoutReadClient.new(subscription: subscription_snapshot("sub_replay", pro.stripe_id, status: "active"))

    with_webhook_settings(client: client, webhook_secret: secret) do
      post_signed(checkout_event("evt_replay_checkout", "sub_replay", pro, created: 1_000), secret)
      assert_response :success
      assert_equal pro.id, @workspace.billing.subscription.price_id
      assert @workspace.billing.unlocked?(:generate_image)

      client.subscription = subscription_snapshot("sub_replay", starter.stripe_id, status: "active")
      post_signed(subscription_updated_event("evt_replay_downgrade", "sub_replay", starter, created: 2_000), secret)
      assert_response :success
      assert_equal starter.id, @workspace.billing.subscription.reload.price_id
      refute @workspace.billing.unlocked?(:generate_image)

      client.subscription = subscription_snapshot("sub_replay", pro.stripe_id, status: "active")
      post_signed(checkout_event("evt_replay_checkout_again", "sub_replay", pro, created: 1_000), secret)
    end

    assert_response :success
    subscription = RecordingStudioStripe::Subscription.find_by!(stripe_id: "sub_replay")
    assert_equal starter.id, subscription.price_id
    assert_equal "active", subscription.status
    refute @workspace.billing.unlocked?(:generate_image)
  end

  test "a resent checkout does not reactivate a canceled plan when Stripe cannot be read" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    secret = "whsec_replay_cancel"
    client = CheckoutReadClient.new(subscription: subscription_snapshot("sub_cancel", pro.stripe_id, status: "active"))

    with_webhook_settings(client: client, webhook_secret: secret) do
      post_signed(checkout_event("evt_cancel_checkout", "sub_cancel", pro, created: 1_000), secret)
      assert_response :success
      post_signed(subscription_deleted_event("evt_cancel_deleted", "sub_cancel"), secret)
      assert_response :success
      assert_equal "canceled", RecordingStudioStripe::Subscription.find_by!(stripe_id: "sub_cancel").status

      client.failure = Stripe::StripeError.new("unavailable")
      post_signed(checkout_event("evt_cancel_replay", "sub_cancel", pro, created: 1_000), secret)
    end

    assert_response :service_unavailable
    assert_equal "canceled", RecordingStudioStripe::Subscription.find_by!(stripe_id: "sub_cancel").status
    refute @workspace.billing.unlocked?(:generate_image)
    refute RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_cancel_replay")
  end

  test "configured checkout stores the subscription price" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    secret = "whsec_live_price"
    client = CheckoutReadClient.new(subscription: subscription_snapshot("sub_live_price", starter.stripe_id, status: "active"))

    with_webhook_settings(client: client, webhook_secret: secret) do
      post_signed(checkout_event("evt_live_price", "sub_live_price", pro, created: 1_700_000_000), secret)
    end

    assert_response :success
    subscription = @workspace.billing.subscription
    assert_equal starter.id, subscription.price_id
    assert_equal "active", subscription.status
    refute @workspace.billing.unlocked?(:generate_image)
  end

  test "a checkout with no event time does not store a plan when Stripe is configured" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    secret = "whsec_no_time"
    client = CheckoutReadClient.new(subscription: subscription_snapshot("sub_no_time", pro.stripe_id, status: "active"))

    with_webhook_settings(client: client, webhook_secret: secret) do
      post_signed(checkout_event("evt_no_time", "sub_no_time", pro, created: nil), secret)
    end

    assert_response :service_unavailable
    assert_nil @workspace.billing.subscription
    refute RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_no_time")
  end

  test "a stripe key without a webhook secret is rejected outside local mode" do
    with_webhook_settings(secret_key: "sk_test_fixture", client: nil, webhook_secret: nil) do
      Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
        refute_predicate RecordingStudioStripe.configuration, :local_mode?
        post_unsigned("evt_key_no_secret")
      end
    end

    assert_response :service_unavailable
    refute RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_key_no_secret")
    refute_includes response.body, "sk_test_fixture"
  end

  test "a missing signature is rejected when the webhook secret is set" do
    with_webhook_settings(webhook_secret: "whsec_test_fixture") do
      post "/webhooks/stripe",
           params: unsigned_body("evt_missing_signature"),
           headers: { "CONTENT_TYPE" => "application/json" }
    end

    assert_response :bad_request
    refute RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_missing_signature")
  end

  test "an older subscription update does not revive a canceled plan in local mode" do
    assert_predicate RecordingStudioStripe.configuration, :local_mode?
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    stripe_id = "sub_local_old_update"

    post_subscription_event(subscription_created_event("evt_local_old_created", stripe_id, price, created: 1_000))
    assert_equal "active", RecordingStudioStripe::Subscription.find_by!(stripe_id: stripe_id).status

    post_subscription_event(subscription_deleted_event("evt_local_old_deleted", stripe_id, created: 3_000))
    deleted = RecordingStudioStripe::Subscription.find_by!(stripe_id: stripe_id)
    assert_equal "canceled", deleted.status
    assert_equal "3000", deleted.metadata["stripe_event_created"]

    post_subscription_event(subscription_updated_event("evt_local_old_update", stripe_id, price, created: 2_000))
    subscription = deleted.reload
    assert_equal "canceled", subscription.status
    assert_equal "3000", subscription.metadata["stripe_event_created"]
    refute @workspace.billing.unlocked?(:generate_image)
  end

  test "a later subscription update does not revive a canceled plan in local mode" do
    assert_predicate RecordingStudioStripe.configuration, :local_mode?
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    stripe_id = "sub_local_new_update"

    post_subscription_event(subscription_created_event("evt_local_new_created", stripe_id, price, created: 1_000))
    post_subscription_event(subscription_deleted_event("evt_local_new_deleted", stripe_id, created: 2_000))
    post_subscription_event(subscription_updated_event("evt_local_new_update", stripe_id, price, created: 3_000))

    subscription = RecordingStudioStripe::Subscription.find_by!(stripe_id: stripe_id)
    assert_equal "canceled", subscription.status
    assert_equal "2000", subscription.metadata["stripe_event_created"]
    refute @workspace.billing.unlocked?(:generate_image)
  end

  test "a subscription update after delete stays canceled when Stripe is read" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    stripe_id = "sub_read_after_delete"
    secret = "whsec_read_after_delete"
    client = CheckoutReadClient.new(subscription: subscription_snapshot(stripe_id, price.stripe_id, status: "active"))

    with_webhook_settings(client: client, webhook_secret: secret) do
      refute_predicate RecordingStudioStripe.configuration, :local_mode?
      post_signed(subscription_created_event("evt_read_created", stripe_id, price, created: 1_000), secret)
      assert_response :success
      assert_equal "active", RecordingStudioStripe::Subscription.find_by!(stripe_id: stripe_id).status

      post_signed(subscription_deleted_event("evt_read_deleted", stripe_id, created: 3_000), secret)
      assert_response :success
      client.subscription = subscription_snapshot(stripe_id, price.stripe_id, status: "canceled")
      post_signed(subscription_updated_event("evt_read_update", stripe_id, price, created: 2_000), secret)
    end

    assert_response :success
    subscription = RecordingStudioStripe::Subscription.find_by!(stripe_id: stripe_id)
    assert_equal "canceled", subscription.status
    assert_equal "3000", subscription.metadata["stripe_event_created"]
    refute @workspace.billing.unlocked?(:generate_image)
    assert_equal "canceled",
                 RecordingStudioStripe::WebhookEvent.find_by!(stripe_id: "evt_read_update").payload["subscription_status"]
  end

  test "a later active Stripe read does not revive a canceled subscription" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    stripe_id = "sub_terminal_read"
    secret = "whsec_terminal_read"
    client = CheckoutReadClient.new(subscription: subscription_snapshot(stripe_id, price.stripe_id, status: "active"))

    with_webhook_settings(client: client, webhook_secret: secret) do
      post_signed(subscription_created_event("evt_terminal_created", stripe_id, price, created: 1_000), secret)
      assert_response :success
      assert_equal "active", RecordingStudioStripe::Subscription.find_by!(stripe_id: stripe_id).status

      post_signed(subscription_deleted_event("evt_terminal_deleted", stripe_id, created: 2_000), secret)
      assert_response :success
      post_signed(subscription_updated_event("evt_terminal_update", stripe_id, price, created: 3_000), secret)
    end

    assert_response :success
    subscription = RecordingStudioStripe::Subscription.find_by!(stripe_id: stripe_id)
    assert_equal "canceled", subscription.status
    assert_equal "2000", subscription.metadata["stripe_event_created"]
    refute @workspace.billing.unlocked?(:generate_image)
  end

  test "a subscription created after a delete is stored canceled from Stripe" do
    assert_late_event_stores_canceled("customer.subscription.created", "sub_delete_then_created")
  end

  test "a subscription updated after a delete is stored canceled from Stripe" do
    assert_late_event_stores_canceled("customer.subscription.updated", "sub_delete_then_updated")
  end

  test "a subscription update is not stored when Stripe cannot be read" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    stripe_id = "sub_read_failed"
    post_subscription_event(subscription_created_event("evt_read_failed_created", stripe_id, price, created: 1_000))
    secret = "whsec_read_failed"
    client = CheckoutReadClient.new(failure: Stripe::StripeError.new("unavailable"))

    with_webhook_settings(client: client, webhook_secret: secret) do
      post_signed(subscription_updated_event("evt_read_failed_update", stripe_id, price, created: 2_000), secret)
    end

    assert_response :service_unavailable
    refute RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_read_failed_update")
    assert_equal "active", RecordingStudioStripe::Subscription.find_by!(stripe_id: stripe_id).status
  end

  test "a subscription create is not stored when Stripe cannot be read" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    secret = "whsec_create_failed"
    client = CheckoutReadClient.new(failure: Stripe::StripeError.new("unavailable"))

    with_webhook_settings(client: client, webhook_secret: secret) do
      post_signed(subscription_created_event("evt_create_failed", "sub_create_failed", price, created: 1_000), secret)
    end

    assert_response :service_unavailable
    refute RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_create_failed")
    assert_nil RecordingStudioStripe::Subscription.find_by(stripe_id: "sub_create_failed")
  end

  test "ApplySubscription does not move a canceled stripe id to another status" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    canceled = RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: price,
      stripe_subscription_id: "sub_apply_terminal",
      stripe_customer_id: "cus_apply_terminal",
      status: "canceled",
      stripe_event_created: 1_000
    )

    revived = RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price,
      stripe_subscription_id: "sub_apply_terminal",
      stripe_customer_id: "cus_apply_terminal",
      status: "active",
      stripe_event_created: 2_000
    )
    other = RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: price,
      stripe_subscription_id: "sub_apply_other",
      stripe_customer_id: "cus_apply_terminal",
      status: "active",
      stripe_event_created: 2_000
    )

    assert_equal canceled.id, revived.id
    assert_equal "canceled", revived.reload.status
    assert_equal price.id, revived.price_id
    assert_equal "1000", revived.metadata["stripe_event_created"]
    assert_equal "active", other.status
    refute_equal canceled.id, other.id
  end

  private

  def post_signed(event, secret)
    payload = event.to_json
    post "/webhooks/stripe",
         params: payload,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "HTTP_STRIPE_SIGNATURE" => signed_header(payload, secret)
         }
  end

  def checkout_event(id, subscription_id, price, created:)
    stripe_event(
      id,
      "checkout.session.completed",
      {
        "id" => "cs_#{subscription_id}",
        "mode" => "subscription",
        "payment_status" => "paid",
        "subscription" => subscription_id,
        "customer" => "cus_#{subscription_id}",
        "client_reference_id" => @root.id.to_s,
        "metadata" => {
          "root_recording_id" => @root.id.to_s,
          "price_id" => price.stripe_id
        }
      },
      created: created
    )
  end

  def post_subscription_event(event)
    post "/webhooks/stripe", params: event, as: :json
    assert_response :success
  end

  def subscription_created_event(id, subscription_id, price, created:, status: "active")
    subscription_change_event("customer.subscription.created", id, subscription_id, price, created: created,
                                                                                          status: status)
  end

  def subscription_updated_event(id, subscription_id, price, created:, status: "active")
    subscription_change_event("customer.subscription.updated", id, subscription_id, price, created: created,
                                                                                          status: status)
  end

  def subscription_change_event(type, id, subscription_id, price, created:, status:)
    stripe_event(
      id,
      type,
      {
        "id" => subscription_id,
        "customer" => "cus_#{subscription_id}",
        "status" => status,
        "cancel_at_period_end" => false,
        "metadata" => { "root_recording_id" => @root.id.to_s },
        "items" => {
          "data" => [
            {
              "id" => "si_#{subscription_id}",
              "price" => { "id" => price.stripe_id },
              "current_period_start" => 1_700_000_000,
              "current_period_end" => 1_702_592_000
            }
          ]
        }
      },
      created: created
    )
  end

  def subscription_deleted_event(id, subscription_id, created: 1_700_000_000)
    stripe_event(
      id,
      "customer.subscription.deleted",
      {
        "id" => subscription_id,
        "customer" => "cus_#{subscription_id}",
        "status" => "canceled"
      },
      created: created
    )
  end

  def subscription_snapshot(id, price_id, status:)
    Stripe::StripeObject.construct_from(
      "id" => id,
      "status" => status,
      "customer" => "cus_#{id}",
      "cancel_at_period_end" => false,
      "metadata" => { "root_recording_id" => @root.id.to_s },
      "items" => {
        "data" => [
          {
            "id" => "si_#{id}",
            "price" => { "id" => price_id },
            "current_period_start" => 1_700_000_000,
            "current_period_end" => 1_702_592_000
          }
        ]
      }
    )
  end

  def assert_late_event_stores_canceled(type, stripe_id)
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    secret = "whsec_#{stripe_id}"
    client = CheckoutReadClient.new(
      subscription: subscription_snapshot(stripe_id, price.stripe_id, status: "canceled")
    )
    event_id = "evt_#{stripe_id}_late"

    with_webhook_settings(client: client, webhook_secret: secret) do
      post_signed(subscription_deleted_event("evt_#{stripe_id}_deleted", stripe_id, created: 2_000), secret)
      assert_response :success
      assert RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_#{stripe_id}_deleted")
      assert_nil RecordingStudioStripe::Subscription.find_by(stripe_id: stripe_id)

      event = subscription_change_event(type, event_id, stripe_id, price, created: 3_000, status: "active")
      post_signed(event, secret)
    end

    assert_response :success
    subscription = RecordingStudioStripe::Subscription.find_by!(stripe_id: stripe_id)
    assert_equal "canceled", subscription.status
    assert_equal "3000", subscription.metadata["stripe_event_created"]
    assert_equal "canceled", RecordingStudioStripe::WebhookEvent.find_by!(stripe_id: event_id).payload["subscription_status"]
    refute @workspace.billing.unlocked?(:generate_image)
  end

  def post_unsigned(event_id)
    post "/webhooks/stripe", params: JSON.parse(unsigned_body(event_id)), as: :json
  end

  def unsigned_body(event_id)
    stripe_event(event_id, "balance.available", { "object" => "balance" }).to_json
  end

  def signed_header(payload, secret)
    timestamp = Time.now
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, secret)
    Stripe::Webhook::Signature.generate_header(timestamp, signature)
  end

  def with_webhook_settings(secret_key: :keep, client: :keep, webhook_secret: :keep)
    configuration = RecordingStudioStripe.configuration
    previous = {
      secret_key: configuration.secret_key,
      client: configuration.client,
      webhook_secret: configuration.webhook_secret
    }
    configuration.secret_key = secret_key unless secret_key == :keep
    configuration.client = client unless client == :keep
    configuration.webhook_secret = webhook_secret unless webhook_secret == :keep
    yield
  ensure
    configuration.secret_key = previous[:secret_key]
    configuration.client = previous[:client]
    configuration.webhook_secret = previous[:webhook_secret]
  end

  def stripe_event(id, type, object, created: 1_700_000_000)
    event = { "id" => id, "object" => "event", "type" => type, "data" => { "object" => object } }
    event["created"] = created unless created.nil?
    event
  end
end

class CheckoutReadClient
  attr_accessor :subscription, :failure

  def initialize(subscription: nil, failure: nil)
    @subscription = subscription
    @failure = failure
  end

  def v1
    self
  end

  def subscriptions
    self
  end

  def retrieve(_id)
    raise failure if failure

    subscription
  end
end
