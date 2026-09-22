# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class PaidTrialTest < ActionDispatch::IntegrationTest
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
    @pro = RecordingStudioStripe::Product.find_by!(name: "Pro")
    @starter = RecordingStudioStripe::Product.find_by!(name: "Starter")
  end

  test "dummy Pro offers a one dollar fourteen day trial" do
    trial = @pro.trial

    assert trial.offered?
    assert_equal 14, trial.days
    assert_equal 100, trial.unit_amount
    assert_equal "Try now", trial.checkout_label
    assert_equal "14 day trial", trial.duration_label
    assert_equal 100, trial.fee_price.unit_amount
    assert_nil trial.fee_price.interval
    assert_equal "trial_fee", trial.fee_price.metadata["kind"]
    assert_equal 2900, @pro.monthly_price.unit_amount
    refute_equal trial.fee_price.id, @pro.monthly_price.id
    refute @starter.trial.offered?
  end

  test "assign trial creates a fee price and deactivates it when the amount changes" do
    RecordingStudioStripe::AssignTrial.call(product: @starter, days: 10, unit_amount: 200)
    @starter.reload
    fee = @starter.trial.fee_price

    assert @starter.trial.offered?
    assert_equal 10, @starter.trial.days
    assert_equal 200, fee.unit_amount
    assert_equal "trial_fee", fee.metadata["kind"]
    assert_nil fee.interval
    assert_equal 900, @starter.monthly_price.unit_amount

    old_id = fee.stripe_id
    RecordingStudioStripe::AssignTrial.call(product: @starter, days: 10, unit_amount: 300)
    @starter.reload
    new_fee = @starter.trial.fee_price

    assert_equal 300, new_fee.unit_amount
    refute_equal old_id, new_fee.stripe_id
    refute @starter.prices.find_by!(stripe_id: old_id).active?

    RecordingStudioStripe::AssignTrial.call(product: @starter, days: "", unit_amount: 300)
    @starter.reload

    refute @starter.trial.offered?
    assert_nil @starter.trial.fee_price
    refute @starter.prices.find_by!(stripe_id: new_fee.stripe_id).active?
  end

  test "assign trial rejects an extra pack" do
    tokens = RecordingStudioStripe::Product.find_by!(kind: "allowance")

    error = assert_raises(RecordingStudioStripe::InvalidPrice) do
      RecordingStudioStripe::AssignTrial.call(product: tokens, days: 7, unit_amount: 100)
    end

    assert_equal "Trials belong on a plan", error.message
  end

  test "start checkout sends trial fields for Pro and not when already subscribed" do
    previous_client = RecordingStudioStripe.configuration.client
    client = RecordingStudioStripe::Testing::Client.new
    RecordingStudioStripe.configuration.client = client
    pro_price = @pro.monthly_price
    starter_price = @starter.monthly_price

    RecordingStudioStripe::StartCheckout.call(
      root_recording: @root,
      price: pro_price,
      actor: @user,
      success_url: "http://www.example.com/billing?checkout=ok",
      cancel_url: "http://www.example.com/plans"
    )
    pro_params = client.last_checkout_params

    assert_equal 14, pro_params[:subscription_data][:trial_period_days]
    assert_equal "always", pro_params[:payment_method_collection]
    assert_equal pro_price.stripe_id, pro_params[:line_items].first[:price]
    assert_equal @pro.trial.fee_price.stripe_id, pro_params[:line_items].last[:price]
    assert_equal 2, pro_params[:line_items].size
    assert_equal pro_price.stripe_id, pro_params[:metadata][:price_id]

    RecordingStudioStripe::StartCheckout.call(
      root_recording: @root,
      price: starter_price,
      actor: @user,
      success_url: "http://www.example.com/billing?checkout=ok",
      cancel_url: "http://www.example.com/plans"
    )
    starter_params = client.last_checkout_params

    refute starter_params[:subscription_data].key?(:trial_period_days)
    refute starter_params.key?(:payment_method_collection)
    assert_equal [{ price: starter_price.stripe_id, quantity: 1 }], starter_params[:line_items]
  ensure
    RecordingStudioStripe.configuration.client = previous_client
  end

  test "start checkout skips trial fields when the group already has a live plan" do
    previous_client = RecordingStudioStripe.configuration.client
    client = RecordingStudioStripe::Testing::Client.new
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: @starter.monthly_price)
    RecordingStudioStripe.configuration.client = client

    result = RecordingStudioStripe::StartCheckout.call(
      root_recording: @root,
      price: @pro.monthly_price,
      actor: @user,
      success_url: "http://www.example.com/billing?checkout=ok",
      cancel_url: "http://www.example.com/plans"
    )

    assert_nil client.last_checkout_params
    assert result[:changed]
    assert_equal @starter.monthly_price.id, @workspace.billing.subscription.price_id
  ensure
    RecordingStudioStripe.configuration.client = previous_client
  end

  test "local checkout writes trialing and a period end of now plus the trial days" do
    travel_to Time.utc(2026, 9, 18, 12, 0, 0) do
      RecordingStudioStripe::StartCheckout.call(
        root_recording: @root,
        price: @pro.monthly_price,
        actor: @user,
        success_url: "http://www.example.com/billing?checkout=ok",
        cancel_url: "http://www.example.com/plans"
      )
    end

    subscription = @workspace.billing.subscription
    assert_equal "trialing", subscription.status
    assert_equal Time.utc(2026, 10, 2, 12, 0, 0), subscription.current_period_end
    assert_equal @pro.monthly_price.id, subscription.price_id
  end

  test "checkout webhook persists trialing when Stripe status is trialing" do
    price = @pro.monthly_price

    post "/webhooks/stripe",
         params: stripe_event(
           "evt_trial_checkout",
           "checkout.session.completed",
           {
             "id" => "cs_trial",
             "mode" => "subscription",
             "payment_status" => "paid",
             "subscription" => { "id" => "sub_trial_checkout", "status" => "trialing" },
             "customer" => "cus_trial_checkout",
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
    assert_equal "trialing", subscription.status
    assert_equal price.id, subscription.price_id
    assert_equal "sub_trial_checkout", subscription.stripe_id
  end

  test "invoice paid does not flip a trialing subscription to active" do
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: @pro.monthly_price,
      stripe_subscription_id: "sub_trial_invoice",
      stripe_customer_id: "cus_trial_invoice",
      status: "trialing"
    )

    post "/webhooks/stripe",
         params: stripe_event(
           "evt_trial_invoice_paid",
           "invoice.paid",
           {
             "id" => "in_trial_paid",
             "paid" => true,
             "parent" => {
               "type" => "subscription_details",
               "subscription_details" => { "subscription" => "sub_trial_invoice" }
             }
           }
         ),
         as: :json

    assert_response :success
    assert_equal "trialing", @workspace.billing.subscription.reload.status
  end

  test "plans and public pricing strike the plan price and offer Try now" do
    get "/plans"

    assert_response :success
    assert_includes response.body, "14 day trial"
    assert_includes response.body, "Try now"
    assert_includes response.body, "Choose plan"
    assert_select "[data-plan-group='studio'] s", text: "$29/mo"
    assert_select "[data-plan-group='studio'] p", text: "$29/mo$1trial"
    assert_includes response.body, "margin-left: 0.25em"
    refute_includes response.body, "Try for $1"
    refute_includes response.body, "Start trial"

    sign_out @user
    get "/pricing"

    assert_response :success
    assert_includes response.body, "Try now"
    assert_includes response.body, "14 day trial"
  end

  test "already subscribed Pro stays Current and Starter stays Downgrade" do
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: @pro.monthly_price)

    get "/plans"

    assert_response :success
    assert_select "button, a", text: "Current plan"
    assert_select "a[href*='subscription/change']", text: "Downgrade"
    refute_includes response.body, "Try now"
    refute_includes response.body, "14 day trial"
  end

  test "upsert product keeps trial metadata when Stripe omits those keys" do
    stripe_product = Struct.new(:id, :name, :description, :active, :metadata, keyword_init: true).new(
      id: @pro.stripe_id,
      name: @pro.name,
      description: @pro.description,
      active: true,
      metadata: { "kind" => "plan", "subscription_type" => "studio" }
    )

    RecordingStudioStripe::UpsertProduct.call(stripe_product)
    @pro.reload

    assert_equal 14, @pro.trial.days
    assert_equal 100, @pro.trial.unit_amount
    assert @pro.trial.offered?
  end

  test "create product sends trial metadata to Stripe" do
    previous_client = RecordingStudioStripe.configuration.client
    client = RecordingStudioStripe::Testing::Client.new
    RecordingStudioStripe.configuration.client = client

    product = RecordingStudioStripe::CreateProduct.call(
      name: "Trial Plan",
      kind: "plan",
      description: "A paid trial.",
      subscription_type: "studio",
      trial_days: 5,
      trial_unit_amount: 250
    )
    stored = client.v1.products.retrieve(product.stripe_id)

    assert_equal "5", stored.metadata[:trial_days] || stored.metadata["trial_days"]
    assert_equal "250", stored.metadata[:trial_unit_amount] || stored.metadata["trial_unit_amount"]
    assert_equal 5, product.trial.days
    assert_equal 250, product.trial.fee_price.unit_amount
  ensure
    RecordingStudioStripe.configuration.client = previous_client
  end

  private

  def stripe_event(id, type, object, created: 1_700_000_000)
    { "id" => id, "object" => "event", "type" => type, "created" => created, "data" => { "object" => object } }
  end
end
