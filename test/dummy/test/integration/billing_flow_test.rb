# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class BillingFlowTest < ActionDispatch::IntegrationTest
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

  test "plans page lists monthly Products" do
    get "/plans"

    assert_response :success
    assert_includes response.body, "Pick a plan"
    assert_includes response.body, "Studio"
    assert_includes response.body, "Inbox"
    assert_includes response.body, "Pro"
    assert_includes response.body, "Starter"
    assert_includes response.body, "Inbox Plus"
    assert_includes response.body, "$29/month"
    assert_includes response.body, "$9/month"
    assert_includes response.body, "$25/month"
    assert_includes response.body, "10m ai tokens"
    assert_includes response.body, "3 press kits"
    assert_includes response.body, "10 press kits"
    assert_includes response.body, "Monthly"
    assert_includes response.body, "Yearly"
    assert_includes response.body, "[border-radius:var(--tabs-pill-corner-radius)]"
    refute_includes response.body, "[&>*]:border-r-0"
    refute_includes response.body, "border-b border-[var(--card-border-color)]"
    refute_includes response.body, "border-t border-[var(--card-border-color)]"
    assert_select "body[data-theme='rounded']", count: 1
    assert_select "html[data-theme='rounded']", count: 1
    assert_select "[data-plans-align='left']", count: 1
    assert_includes response.body, "justify-start"
    assert_select "form[action*='checkout'][data-turbo=false]"
    refute_includes response.body, "Unlimited vibes"
    refute_includes response.body, "Add included usage on the Price"
  end

  test "public pricing page centers the plan cards" do
    sign_out @user
    get "/pricing"

    assert_response :success
    assert_includes response.body, "Pick a plan"
    assert_includes response.body, "Studio"
    assert_includes response.body, "Inbox"
    assert_includes response.body, "Pro"
    assert_includes response.body, "Starter"
    assert_includes response.body, "$29/month"
    assert_select "html[data-theme='rounded']", count: 1
    assert_select "[data-plans-align='center']", count: 1
    assert_includes response.body, "justify-center"
    refute_includes response.body, "data-recording-studio-default-layout"
  end

  test "public pricing page shows yearly Prices" do
    sign_out @user
    get "/pricing", params: { interval: "year" }

    assert_response :success
    assert_includes response.body, "$290/year"
    assert_includes response.body, "$90/year"
    assert_select "[data-plans-align='center']", count: 1
  end

  test "plans page shows yearly Prices on the same Products" do
    get "/plans", params: { interval: "year" }

    assert_response :success
    assert_includes response.body, "Pro"
    assert_includes response.body, "Starter"
    assert_includes response.body, "Inbox Plus"
    assert_includes response.body, "$290/year"
    assert_includes response.body, "$90/year"
    assert_includes response.body, "$250/year"
  end

  test "plans page toggles monthly and yearly per group" do
    get "/plans", params: { interval: { studio: "year" } }

    assert_response :success
    assert_select "[data-plan-group='studio'] [data-plan-group-heading]", count: 1
    assert_select "[data-plan-group='inbox'] [data-plan-group-heading]", count: 1
    assert_select "[data-plan-group-heading].items-start", count: 2
    assert_select "[data-plan-group='studio'] a", text: "Yearly"
    assert_select "[data-plan-group='inbox'] a", text: "Yearly"
    assert_select "[aria-label='Studio yearly']"
    assert_select "[aria-label='Inbox monthly']"
    assert_includes response.body, "$290/year"
    assert_includes response.body, "$90/year"
    assert_includes response.body, "$25/month"
    assert_includes response.body, "$50/month"
    refute_includes response.body, "$250/year"
    refute_includes response.body, "$500/year"
  end

  test "plans component rejects an unknown align" do
    error = assert_raises ArgumentError do
      RecordingStudioStripe::PlansComponent.new(
        products: [],
        interval: "month",
        monthly_href: "/plans",
        yearly_href: "/plans?interval=year",
        align: :right
      )
    end

    assert_match(/left or :center/, error.message)
  end

  test "checkout in local mode starts a subscription" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    post recording_studio_stripe.checkout_path, params: { price_id: price.id }

    assert_redirected_to %r{/billing}
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Pro"
    assert_predicate @workspace.billing.subscription, :active?
    assert @workspace.billing.unlocked?(:generate_image)
    refute @workspace.billing.unlocked?(:export_csv)
    assert RecordingStudioAccessible.authorized_action?(
      actor: @user,
      action: :generate_image,
      recording: @root
    )
    refute RecordingStudioAccessible.authorized_action?(
      actor: @user,
      action: :export_csv,
      recording: @root
    )
  end

  test "upgrade takes effect immediately" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: starter)

    patch recording_studio_stripe.subscription_path, params: { price_id: pro.id }

    follow_redirect!
    assert_equal pro.id, @workspace.billing.subscription.price_id
    refute @workspace.billing.subscription.scheduled_downgrade?
  end

  test "upgrade and switch open a confirmation page first" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: starter)

    get "/plans"

    assert_response :success
    assert_select "a[href*='subscription/change'][href*='#{pro.id}']", text: "Upgrade"
    refute_select "form[action*='subscription'][method='post']"

    get recording_studio_stripe.subscription_change_path, params: { price_id: pro.id }

    assert_response :success
    assert_includes response.body, "Upgrade to Pro?"
    assert_includes response.body, "You pay the difference today."
    assert_includes response.body, "Now"
    assert_includes response.body, "Next"
    assert_includes response.body, "Starter"
    assert_includes response.body, "Pro"
    assert_includes response.body, "$9/month"
    assert_includes response.body, "$29/month"
    assert_includes response.body, "Keep this plan"
    assert_select "form[action*='subscription']"
  end

  test "downgrade confirmation names the renewal" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: pro,
      current_period_end: Time.utc(2026, 10, 12)
    )

    get recording_studio_stripe.subscription_change_path, params: { price_id: starter.id }

    assert_response :success
    assert_includes response.body, "Switch to Starter?"
    assert_includes response.body, "Starter starts on October 12, 2026. You keep Pro until then."
    assert_includes response.body, "From renewal"
    assert_includes response.body, "Switch at renewal"
  end

  test "confirmation without a live plan sends you back to plans" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    get recording_studio_stripe.subscription_change_path, params: { price_id: pro.id }

    assert_redirected_to %r{/plans}
  end

  test "checkout for a live type opens confirmation instead of changing immediately" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: starter)

    assert_no_difference -> { RecordingStudioStripe::Subscription.where(root_recording_id: @root.id).count } do
      post recording_studio_stripe.checkout_path, params: { price_id: pro.id }
    end

    assert_redirected_to recording_studio_stripe.subscription_change_path(price_id: pro.id)
    assert_equal starter.id, @workspace.billing.line(:studio).subscription.price_id

    follow_redirect!
    assert_includes response.body, "Upgrade to Pro?"

    patch recording_studio_stripe.subscription_path, params: { price_id: pro.id }

    follow_redirect!
    assert_equal pro.id, @workspace.billing.line(:studio).subscription.price_id
  end

  test "downgrade schedules for renewal" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)

    patch recording_studio_stripe.subscription_path, params: { price_id: starter.id }

    follow_redirect!
    subscription = @workspace.billing.subscription
    assert_equal pro.id, subscription.price_id
    assert_equal starter.id, subscription.scheduled_price_id
  end

  test "billing explains the wait when checkout returns before Stripe writes" do
    get recording_studio_stripe.root_path, params: { checkout: "ok" }

    assert_response :success
    assert_includes response.body, "Stripe is confirming this plan"
    refute_includes response.body, "You're on"
  end

  test "change plan reads the Stripe item id when metadata is missing" do
    previous_client = RecordingStudioStripe.configuration.client
    client = RecordingStudioStripe::Testing::Client.new
    RecordingStudioStripe.configuration.client = client
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    subscription = RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: starter,
      stripe_subscription_id: "sub_item_lookup"
    )
    subscription.update!(metadata: {})

    RecordingStudioStripe::ChangePlan.call(root_recording: @root, price: pro)

    assert_equal starter.id, @workspace.billing.subscription.reload.price_id
    assert_equal "si_item_lookup", @workspace.billing.subscription.metadata["stripe_item_id"]
  ensure
    RecordingStudioStripe.configuration.client = previous_client
  end

  test "downgrade creates a schedule then updates phases" do
    previous_client = RecordingStudioStripe.configuration.client
    client = RecordingStudioStripe::Testing::Client.new
    RecordingStudioStripe.configuration.client = client
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: pro,
      stripe_subscription_id: "sub_down"
    )

    RecordingStudioStripe::ChangePlan.call(root_recording: @root, price: starter)

    assert_equal [{ from_subscription: "sub_down" }], client.schedule_creates
    phases = client.schedule_updates.first[:phases]
    assert_equal 2, phases.size
    assert_equal starter.stripe_id, phases.last[:items].first[:price]
    assert_equal starter.id, @workspace.billing.subscription.reload.scheduled_price_id
    assert_equal pro.id, @workspace.billing.subscription.price_id
  ensure
    RecordingStudioStripe.configuration.client = previous_client
  end

  test "allowance checkout uses a new idempotency key each time" do
    previous_client = RecordingStudioStripe.configuration.client
    client = RecordingStudioStripe::Testing::Client.new
    RecordingStudioStripe.configuration.client = client
    pack = RecordingStudioStripe::Price.one_time.find_by!("metadata ->> 'allowance' = '5000000'")

    2.times do
      RecordingStudioStripe::StartCheckout.call(
        root_recording: @root,
        price: pack,
        actor: @user,
        success_url: "http://www.example.com/billing?checkout=ok",
        cancel_url: "http://www.example.com/plans"
      )
    end

    keys = client.checkout_idempotency_keys
    assert_equal 2, keys.uniq.size
    keys.each { |key| assert_match(/\Acheckout-.+-#{Regexp.escape(pack.stripe_id)}-/, key) }
  ensure
    RecordingStudioStripe.configuration.client = previous_client
  end

  test "cancel stays active until period end" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)

    post recording_studio_stripe.subscription_cancel_path

    follow_redirect!
    assert_predicate @workspace.billing.subscription, :canceling?
    assert_predicate @workspace.billing.subscription, :active?
  end

  test "meter remaining is included plus purchased minus usage" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    pack = RecordingStudioStripe::Price.one_time.find_by!("metadata ->> 'allowance' = '5000000'")
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)
    RecordingStudioStripe::ApplyAllowance.call(root_recording: @root, price: pack)

    meter = @workspace.billing.meter(:ai_tokens)
    meter.record(1_000_000)

    assert_equal 10_000_000, meter.included
    assert_equal 5_000_000, meter.purchased
    assert_equal 1_000_000, meter.usage
    assert_equal 14_000_000, meter.remaining
    assert meter.available?(14_000_000)
    refute meter.available?(14_000_001)

    meter.spend(1)
    assert_equal 1_000_001, meter.usage
    meter.spend(100, idempotency_key: "tok-retry")
    meter.spend(100, idempotency_key: "tok-retry")
    assert_equal 1_000_101, @workspace.billing.meter(:ai_tokens).usage
    error = assert_raises(RecordingStudioStripe::MeterLimitReached) { meter.spend(14_000_000) }
    assert_includes error.user_message, "ai tokens"
    meter.record(14_000_000)
    assert_equal 15_000_101, @workspace.billing.meter(:ai_tokens).usage
  end

  test "billing page shows usage percent" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)

    get recording_studio_stripe.root_path

    assert_response :success
    assert_includes response.body, "Studio usage"
    assert_includes response.body, "AI tokens"
    assert_includes response.body, "0%"
    assert_includes response.body, "+5m ai tokens"
    refute_includes response.body, "10m left"
    refute_includes response.body, "Included 10m"
    assert_includes response.body, "md:grid-cols-2"
    assert_includes response.body, "badge-primary-background-color"
  end

  test "buying an extra pack increases remaining" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    pack = RecordingStudioStripe::Price.one_time.find_by!("metadata ->> 'allowance' = '5000000'")
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)

    post recording_studio_stripe.allowances_path, params: { price_id: pack.id }

    follow_redirect!
    assert_equal 15_000_000, @workspace.billing.meter(:ai_tokens).remaining
  end

  test "billing hides manage billing before a customer exists" do
    get recording_studio_stripe.root_path

    assert_response :success
    refute_includes response.body, "Manage billing on Stripe"
    assert_includes response.body, "Usage still counts if you record it"
    refute_includes response.body, "Unlimited vibes"
  end

  test "manage billing shows when a customer exists without an active plan" do
    RecordingStudioStripe::EnsureCustomer.call(root_recording: @root, email: @user.email)

    get recording_studio_stripe.root_path

    assert_response :success
    assert_includes response.body, "No plan yet"
    assert_includes response.body, "Manage billing on Stripe"
  end

  test "manage billing shows after checkout and stays local without keys" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    post recording_studio_stripe.checkout_path, params: { price_id: price.id }
    follow_redirect!

    assert_response :success
    assert_includes response.body, "Manage billing on Stripe"
    assert_includes response.body, "credit-card"
    assert_includes response.body, recording_studio_stripe.portal_path

    post recording_studio_stripe.portal_path

    assert_redirected_to %r{/billing}
    follow_redirect!
    assert_includes response.body, "Invoices and cards live in Stripe. Add keys to open them."
  end

  test "ensure customer updates email" do
    customer = RecordingStudioStripe::EnsureCustomer.call(root_recording: @root, email: "first@example.com")
    RecordingStudioStripe::EnsureCustomer.call(root_recording: @root, email: "next@example.com")

    assert_equal "next@example.com", customer.reload.email
  end

  test "product update merges Stripe metadata" do
    previous_client = RecordingStudioStripe.configuration.client
    client = RecordingStudioStripe::Testing::Client.new
    RecordingStudioStripe.configuration.client = client
    product = RecordingStudioStripe::Product.find_by!(name: "Starter")
    client.v1.products.update(product.stripe_id, metadata: { "tax_code" => "txcd_1", "kind" => "plan" })

    RecordingStudioStripe::UpdateProduct.call(
      product: product,
      name: product.name,
      description: product.description,
      paywall_names: product.paywalls.map(&:name),
      limits: { "press_kits" => 3 }
    )

    stored = client.v1.products.retrieve(product.stripe_id)
    assert_equal "txcd_1", stored.metadata["tax_code"]
    assert_equal "3", stored.metadata["limit_press_kits"]

    RecordingStudioStripe::UpdateProduct.call(
      product: product.reload,
      name: product.name,
      description: product.description,
      paywall_names: product.paywalls.map(&:name),
      limits: { "press_kits" => "" }
    )

    stored = client.v1.products.retrieve(product.stripe_id)
    assert_equal "txcd_1", stored.metadata["tax_code"]
    assert_equal "", stored.metadata["limit_press_kits"]
  ensure
    RecordingStudioStripe.configuration.client = previous_client
  end

  test "portal redirects to Stripe when a client is set" do
    previous_client = RecordingStudioStripe.configuration.client
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)
    RecordingStudioStripe.configuration.client = RecordingStudioStripe::Testing::Client.new

    post recording_studio_stripe.portal_path

    assert_redirected_to %r{\Ahttps://billing.stripe.test}
  ensure
    RecordingStudioStripe.configuration.client = previous_client
  end

  test "view access can see billing and cannot open the portal" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)
    viewer = User.find_or_create_by!(email: "viewer@example.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    grant_owner_access!(recording: @root, actor: viewer, role: :view)
    sign_out @user
    sign_in viewer
    switch_to_root!(@root)

    get recording_studio_stripe.root_path

    assert_response :success
    refute_includes response.body, "Manage billing on Stripe"

    post recording_studio_stripe.portal_path

    assert_response :forbidden
  end

  test "starter does not open generate_image" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: starter)

    refute @workspace.billing.unlocked?(:generate_image)
    refute RecordingStudioAccessible.authorized_action?(
      actor: @user,
      action: :generate_image,
      recording: @root
    )
  end

  test "starter does not open generate_image until Pro" do
    get "/"

    assert_response :success
    refute_includes response.body, "What this plan opens"
    refute RecordingStudioAccessible.authorized_action?(
      actor: @user,
      action: :generate_image,
      recording: @root
    )

    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)

    assert RecordingStudioAccessible.authorized_action?(
      actor: @user,
      action: :generate_image,
      recording: @root
    )
  end
end
