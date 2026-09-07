# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class StripeHardeningTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_owner_access!(recording: @root, actor: @user)
    sign_in @user
    switch_to_root!(@root)
  end

  test "two first checkouts in one group keep one pending row" do
    previous_client = RecordingStudioStripe.configuration.client
    client = RecordingStudioStripe::Testing::Client.new
    RecordingStudioStripe.configuration.client = client
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    RecordingStudioStripe::StartCheckout.call(
      root_recording: @root,
      price: starter,
      actor: @user,
      success_url: "http://www.example.com/billing?checkout=ok",
      cancel_url: "http://www.example.com/plans"
    )
    RecordingStudioStripe::StartCheckout.call(
      root_recording: @root,
      price: pro,
      actor: @user,
      success_url: "http://www.example.com/billing?checkout=ok",
      cancel_url: "http://www.example.com/plans"
    )

    pending = RecordingStudioStripe::Subscription.where(root_recording_id: @root.id, status: "incomplete")
    assert_equal 1, pending.count
    assert_equal pro.id, pending.first.price_id
    assert_equal 1, client.expired_sessions.size
    refute RecordingStudioStripe::Subscription.current.exists?(root_recording_id: @root.id)
  ensure
    RecordingStudioStripe.configuration.client = previous_client
  end

  test "automatic tax checkout also sends customer address auto" do
    previous_client = RecordingStudioStripe.configuration.client
    previous_tax = RecordingStudioStripe.configuration.automatic_tax
    client = RecordingStudioStripe::Testing::Client.new
    RecordingStudioStripe.configuration.client = client
    RecordingStudioStripe.configuration.automatic_tax = true
    price = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price

    RecordingStudioStripe::StartCheckout.call(
      root_recording: @root,
      price: price,
      actor: @user,
      success_url: "http://www.example.com/billing?checkout=ok",
      cancel_url: "http://www.example.com/plans"
    )

    params = client.last_checkout_params
    assert_equal({ enabled: true }, params[:automatic_tax])
    assert_equal({ address: "auto" }, params[:customer_update])
  ensure
    RecordingStudioStripe.configuration.client = previous_client
    RecordingStudioStripe.configuration.automatic_tax = previous_tax
  end

  test "unpaid checkout.session.completed does not grant a plan" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    post "/webhooks/stripe",
         params: stripe_event(
           "evt_unpaid_checkout",
           "checkout.session.completed",
           {
             "id" => "cs_unpaid",
             "mode" => "subscription",
             "payment_status" => "unpaid",
             "subscription" => "sub_unpaid",
             "customer" => "cus_unpaid",
             "client_reference_id" => @root.id.to_s,
             "metadata" => {
               "root_recording_id" => @root.id.to_s,
               "price_id" => price.stripe_id
             }
           }
         ),
         as: :json

    assert_response :success
    assert_nil @workspace.billing.subscription
  end

  test "async payment success fulfils checkout" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    post "/webhooks/stripe",
         params: stripe_event(
           "evt_async_pay",
           "checkout.session.async_payment_succeeded",
           {
             "id" => "cs_async",
             "mode" => "subscription",
             "payment_status" => "paid",
             "subscription" => "sub_async",
             "customer" => "cus_async",
             "client_reference_id" => @root.id.to_s,
             "metadata" => {
               "root_recording_id" => @root.id.to_s,
               "price_id" => price.stripe_id
             }
           }
         ),
         as: :json

    assert_response :success
    assert_equal price.id, @workspace.billing.subscription.price_id
    assert_equal "sub_async", @workspace.billing.subscription.stripe_id
  end

  test "incomplete upgrade keeps the local price" do
    previous_client = RecordingStudioStripe.configuration.client
    client = RecordingStudioStripe::Testing::Client.new
    client.fail_incomplete_upgrades!
    RecordingStudioStripe.configuration.client = client
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: starter,
      stripe_subscription_id: "sub_incomplete"
    )

    RecordingStudioStripe::ChangePlan.call(root_recording: @root, price: pro)

    assert_equal starter.id, @workspace.billing.subscription.reload.price_id
  ensure
    RecordingStudioStripe.configuration.client = previous_client
  end

  test "stale subscription webhook does not rewind a newer price" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    post "/webhooks/stripe", params: subscription_event("evt_new", "sub_order", pro, created: 2_000), as: :json
    post "/webhooks/stripe", params: subscription_event("evt_old", "sub_order", starter, created: 1_000), as: :json

    assert_response :success
    assert_equal pro.id, @workspace.billing.subscription.reload.price_id
  end

  test "customer unique failures are not treated as duplicate webhooks" do
    RecordingStudioStripe::EnsureCustomer.call(root_recording: @root, email: @user.email)
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    assert_raises(ActiveRecord::RecordInvalid) do
      RecordingStudioStripe::ProcessWebhook.call(
        payload: subscription_event("evt_cus_conflict", "sub_conflict", price, customer: "cus_other").to_json,
        signature: nil
      )
    end
    refute RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_cus_conflict")
  end

  test "product and price webhooks upsert the catalogue" do
    post "/webhooks/stripe",
         params: stripe_event(
           "evt_prod_up",
           "product.created",
           {
             "id" => "prod_webhook",
             "name" => "Webhook Plan",
             "active" => true,
             "metadata" => { "kind" => "plan", "subscription_type" => "studio" }
           }
         ),
         as: :json

    assert_response :success
    product = RecordingStudioStripe::Product.find_by!(stripe_id: "prod_webhook")
    assert_equal "Webhook Plan", product.name

    post "/webhooks/stripe",
         params: stripe_event(
           "evt_price_up",
           "price.created",
           {
             "id" => "price_webhook",
             "product" => "prod_webhook",
             "unit_amount" => 1200,
             "currency" => "usd",
             "active" => true,
             "recurring" => { "interval" => "month" },
             "metadata" => {}
           }
         ),
         as: :json

    assert_response :success
    price = RecordingStudioStripe::Price.find_by!(stripe_id: "price_webhook")
    assert_equal 1200, price.unit_amount
    assert_equal product.id, price.product_id
  end

  test "resume talks to Stripe when a client is set" do
    previous_client = RecordingStudioStripe.configuration.client
    client = RecordingStudioStripe::Testing::Client.new
    RecordingStudioStripe.configuration.client = client
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: pro,
      stripe_subscription_id: "sub_resume"
    )
    RecordingStudioStripe::CancelSubscription.call(root_recording: @root, subscription_type: "studio")

    RecordingStudioStripe::ResumeSubscription.call(root_recording: @root, subscription_type: "studio")

    stored = client.v1.subscriptions.retrieve("sub_resume")
    refute stored.cancel_at_period_end
    refute @workspace.billing.line(:studio).subscription.reload.cancel_at_period_end
  ensure
    RecordingStudioStripe.configuration.client = previous_client
  end

  test "upgrade releases an existing Stripe schedule" do
    previous_client = RecordingStudioStripe.configuration.client
    client = RecordingStudioStripe::Testing::Client.new
    RecordingStudioStripe.configuration.client = client
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: starter,
      stripe_subscription_id: "sub_sched"
    )
    client.v1.subscriptions.retrieve("sub_sched").schedule = "sub_sched_existing"

    RecordingStudioStripe::ChangePlan.call(root_recording: @root, price: pro)

    assert_equal starter.id, @workspace.billing.subscription.reload.price_id
  ensure
    RecordingStudioStripe.configuration.client = previous_client
  end

  test "edit access cannot start checkout" do
    editor = User.find_or_create_by!(email: "editor@example.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    grant_owner_access!(recording: @root, actor: editor, role: :edit)
    sign_out @user
    sign_in editor
    switch_to_root!(@root)
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    post recording_studio_stripe.checkout_path, params: { price_id: price.id }

    assert_response :forbidden
    refute @workspace.billing.subscribed?
  end

  test "allowance prices cannot go through plan checkout" do
    pack = RecordingStudioStripe::Price.one_time.find_by!("metadata ->> 'allowance' = '5000000'")

    post recording_studio_stripe.checkout_path, params: { price_id: pack.id }

    assert_redirected_to %r{/plans}
    refute @workspace.billing.subscribed?
  end

  test "plan prices cannot go through allowance checkout" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    post recording_studio_stripe.allowances_path, params: { price_id: price.id }

    follow_redirect!
    refute @workspace.billing.subscribed?
  end

  test "cancel without a type is rejected when two live plans exist" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    inbox = RecordingStudioStripe::Product.find_by!(name: "Inbox").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: inbox)

    error = assert_raises(RecordingStudioStripe::NoSubscription) do
      RecordingStudioStripe::CancelSubscription.call(root_recording: @root)
    end
    assert_includes error.message, "which plan"
  end

  test "meter named does not insert unknown names" do
    assert_nil RecordingStudioStripe::Meter.named("not_a_real_meter")
    refute RecordingStudioStripe::Meter.exists?(name: "not_a_real_meter")
    assert_raises(ArgumentError) { RecordingStudioStripe::Meter.fetch("not_a_real_meter") }
  end

  test "usage idempotency keys are scoped to the workspace" do
    other = Workspace.create!(name: "Other Workspace #{SecureRandom.hex(4)}")
    other_root = RecordingStudio.root_recording_for(other)
    meter = RecordingStudioStripe::Meter.fetch("ai_tokens")

    first = RecordingStudioStripe::RecordUsage.call(
      root_recording: @root,
      meter: meter,
      quantity: 3,
      idempotency_key: "shared-key"
    )
    second = RecordingStudioStripe::RecordUsage.call(
      root_recording: other_root,
      meter: meter,
      quantity: 5,
      idempotency_key: "shared-key"
    )
    retry_first = RecordingStudioStripe::RecordUsage.call(
      root_recording: @root,
      meter: meter,
      quantity: 9,
      idempotency_key: "shared-key"
    )

    assert_equal first.id, retry_first.id
    refute_equal first.id, second.id
    assert_equal 3, first.quantity
    assert_equal 5, second.quantity
  end

  test "packs bought before subscribe still count in the new period" do
    pack = RecordingStudioStripe::Price.one_time.find_by!("metadata ->> 'allowance' = '5000000'")
    RecordingStudioStripe::ApplyAllowance.call(root_recording: @root, price: pack)
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: pro,
      current_period_start: Time.current.beginning_of_month + 12.hours,
      current_period_end: 1.month.from_now
    )

    assert_equal 5_000_000, @workspace.billing.meter(:ai_tokens).purchased
  end

  test "portal Stripe errors redirect with a human flash" do
    previous_client = RecordingStudioStripe.configuration.client
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)
    client = RecordingStudioStripe::Testing::Client.new
    client.fail_portal!
    RecordingStudioStripe.configuration.client = client

    post recording_studio_stripe.portal_path

    assert_redirected_to %r{/billing}
    follow_redirect!
    assert_includes response.body, "Stripe could not open billing"
  ensure
    RecordingStudioStripe.configuration.client = previous_client
  end

  test "create price rejects a nonnumeric amount" do
    error = assert_raises(RecordingStudioStripe::InvalidPrice) do
      RecordingStudioStripe::CreatePrice.call(
        product: RecordingStudioStripe::Product.find_by!(name: "Starter"),
        unit_amount: "twelve"
      )
    end
    assert_includes error.message, "whole number"
  end

  test "webhook payload stores ids not the full event" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    post "/webhooks/stripe", params: subscription_event("evt_small_payload", "sub_small", price), as: :json

    payload = RecordingStudioStripe::WebhookEvent.find_by!(stripe_id: "evt_small_payload").payload
    assert_equal "evt_small_payload", payload["id"]
    assert_equal "sub_small", payload["object_id"]
    refute payload.key?("data")
  end

  test "line meters keep usage on their own group" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    inbox = RecordingStudioStripe::Product.find_by!(name: "Inbox Plus").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: inbox)

    @workspace.billing.line(:studio).meter(:ai_tokens).record(100)
    @workspace.billing.line(:inbox).meter(:api_calls).record(4)

    assert_equal 100, @workspace.billing.line(:studio).meter(:ai_tokens).usage
    assert_equal 0, @workspace.billing.line(:inbox).meter(:ai_tokens).usage
    assert_equal 4, @workspace.billing.line(:inbox).meter(:api_calls).usage
  end

  private

  def stripe_event(id, type, object, created: 1_700_000_000)
    { "id" => id, "object" => "event", "type" => type, "created" => created, "data" => { "object" => object } }
  end

  def subscription_event(id, stripe_id, price, created: 1_700_000_000, customer: "cus_#{stripe_id}")
    stripe_event(
      id,
      "customer.subscription.updated",
      {
        "id" => stripe_id,
        "customer" => customer,
        "status" => "active",
        "cancel_at_period_end" => false,
        "metadata" => { "root_recording_id" => @root.id.to_s },
        "items" => {
          "data" => [
            {
              "id" => "si_#{stripe_id}",
              "price" => { "id" => price.stripe_id },
              "current_period_start" => 1.day.ago.to_i,
              "current_period_end" => 29.days.from_now.to_i
            }
          ]
        }
      },
      created: created
    )
  end
end
