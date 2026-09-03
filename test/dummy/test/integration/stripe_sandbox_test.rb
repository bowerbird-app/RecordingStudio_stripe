# frozen_string_literal: true

require "test_helper"

class StripeSandboxTest < ActiveSupport::TestCase
  setup do
    skip "Set STRIPE_SANDBOX_TEST=0 to skip live Stripe sandbox tests" if ENV["STRIPE_SANDBOX_TEST"] == "0"

    @secret = RecordingStudioStripe::Configuration.env_secret_key
    skip "Set Stripe_secret_key or STRIPE_SECRET_KEY (test mode) to run sandbox tests" if @secret.blank?
    skip "Refusing live Stripe keys. Use a sandbox sk_test_ or rk_test_ key." if RecordingStudioStripe::Configuration.live_secret_key?(@secret)
    skip "Stripe sandbox tests need a test-mode secret key" unless RecordingStudioStripe::Configuration.sandbox_test_key?(@secret)

    @previous_secret = RecordingStudioStripe.configuration.secret_key
    @previous_publishable = RecordingStudioStripe.configuration.publishable_key
    @previous_client = RecordingStudioStripe.configuration.client
    RecordingStudioStripe.configuration.secret_key = @secret
    RecordingStudioStripe.configuration.publishable_key = RecordingStudioStripe::Configuration.env_publishable_key
    RecordingStudioStripe.configuration.client = nil
    @created = { products: [], prices: [], customers: [], subscriptions: [] }

    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @workspace = Workspace.create!(name: "Sandbox #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
  end

  teardown do
    cleanup_stripe_objects
    RecordingStudioStripe.configuration.secret_key = @previous_secret
    RecordingStudioStripe.configuration.publishable_key = @previous_publishable
    RecordingStudioStripe.configuration.client = @previous_client
  end

  test "sandbox keys create a Product, Customer, Checkout Session, and Subscription" do
    product = RecordingStudioStripe::CreateProduct.call(
      name: "Sandbox probe #{SecureRandom.hex(4)}",
      kind: "plan",
      description: "Recording Studio Stripe sandbox probe"
    )
    @created[:products] << product.stripe_id
    refute_prefix "prod_local_", product.stripe_id

    price = RecordingStudioStripe::CreatePrice.call(
      product: product,
      unit_amount: 500,
      interval: "month",
      metadata: { "included_ai_tokens" => "1000", "included_api_calls" => "10" }
    )
    @created[:prices] << price.stripe_id
    refute_prefix "price_local_", price.stripe_id

    customer = RecordingStudioStripe::EnsureCustomer.call(
      root_recording: @root,
      email: "sandbox+#{SecureRandom.hex(4)}@example.invalid"
    )
    @created[:customers] << customer.stripe_id
    assert customer.stripe_id.start_with?("cus_")
    refute_prefix "cus_local_", customer.stripe_id

    checkout = RecordingStudioStripe::StartCheckout.call(
      root_recording: @root,
      price: price,
      actor: @user,
      success_url: "https://example.com/billing?checkout=ok",
      cancel_url: "https://example.com/plans"
    )

    assert checkout[:url].start_with?("https://checkout.stripe.com/")
    assert checkout[:session_id].start_with?("cs_")
    refute checkout[:local]

    session = stripe_client.v1.checkout.sessions.retrieve(checkout[:session_id])
    assert_equal "subscription", session_value(session, :mode)
    assert_equal customer.stripe_id, session_value(session, :customer)
    assert_equal @root.id.to_s, session_metadata(session, "root_recording_id")
    identifier = session_value(session, :integration_identifier)
    assert_match(/\Arecording-studio-[a-z0-9]{8}\z/, identifier.to_s) if identifier.present?

    subscription = pay_and_project!(customer: customer, price: price)
    @created[:subscriptions] << subscription.stripe_id

    local = @workspace.billing.subscription
    assert_predicate local, :active?
    assert_equal price.id, local.price_id
    assert local.stripe_id.start_with?("sub_")
  end

  test "demo catalogue seeds onto the Stripe sandbox" do
    reset_demo_catalog_to_local_ids
    RecordingStudioStripe::SeedDemoCatalog.call

    pro = RecordingStudioStripe::Product.find_by!(name: "Pro")
    refute_prefix "prod_local_", pro.stripe_id
    refute_prefix "price_local_", pro.monthly_price.stripe_id

    retrieved = stripe_client.v1.products.retrieve(pro.stripe_id)
    assert_equal "Pro", session_value(retrieved, :name)
  end

  private

  def stripe_client
    RecordingStudioStripe::Client.current
  end

  def pay_and_project!(customer:, price:)
    payment_method = stripe_client.v1.payment_methods.create(
      { type: "card", card: { token: "tok_visa" } }
    )
    stripe_client.v1.payment_methods.attach(payment_method.id, { customer: customer.stripe_id })
    stripe_client.v1.customers.update(
      customer.stripe_id,
      { invoice_settings: { default_payment_method: payment_method.id } }
    )
    stripe_subscription = stripe_client.v1.subscriptions.create(
      {
        customer: customer.stripe_id,
        items: [{ price: price.stripe_id }],
        metadata: { root_recording_id: @root.id.to_s }
      }
    )

    ProcessWebhook.call(
      payload: subscription_event_payload(stripe_subscription).to_json,
      signature: nil
    )

    RecordingStudioStripe::Subscription.find_by!(stripe_id: stripe_subscription.id)
  end

  def subscription_event_payload(stripe_subscription)
    {
      "id" => "evt_sandbox_#{SecureRandom.hex(8)}",
      "object" => "event",
      "type" => "customer.subscription.created",
      "data" => { "object" => stripe_object_hash(stripe_subscription) }
    }
  end

  def stripe_object_hash(object)
    return object.to_hash if object.respond_to?(:to_hash)
    return object.as_json if object.respond_to?(:as_json)

    JSON.parse(object.to_json)
  end

  def session_value(object, key)
    return object.public_send(key) if object.respond_to?(key)
    return object[key] || object[key.to_s] if object.respond_to?(:[])

    nil
  end

  def session_metadata(object, key)
    metadata = session_value(object, :metadata)
    return if metadata.blank?
    return metadata[key] || metadata[key.to_s] || metadata[key.to_sym] if metadata.respond_to?(:[])

    metadata.public_send(key) if metadata.respond_to?(key)
  end

  def refute_prefix(prefix, value)
    refute value.start_with?(prefix), "expected #{value.inspect} not to start with #{prefix.inspect}"
  end

  def cleanup_stripe_objects
    return if @created.blank? || @secret.blank?

    Array(@created[:subscriptions]).each do |id|
      stripe_client.v1.subscriptions.cancel(id)
    rescue Stripe::StripeError
      nil
    end
    Array(@created[:products]).each do |id|
      stripe_client.v1.products.update(id, { active: false })
    rescue Stripe::StripeError
      nil
    end
  rescue MissingStripeKey
    nil
  end
end
