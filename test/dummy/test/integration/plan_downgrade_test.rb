# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class PlanDowngradeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  EVENT = RecordingStudioStripe::DomainEvents::PLAN_DOWNGRADED
  CREATED = 1_700_000_000

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
    @team = RecordingStudioStripe::Product.find_by!(name: "Team")
    @previous_types = RecordingStudioStripe.configuration.subscription_types
  end

  teardown do
    RecordingStudioStripe.configuration.subscription_types = @previous_types
    RecordingStudioStripe.configuration.client = nil
  end

  test "default timing still schedules a downgrade at renewal" do
    client = use_stripe_client
    pro = @pro.monthly_price
    starter = @starter.monthly_price
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: pro,
      stripe_subscription_id: "sub_sched_default",
      stripe_customer_id: "cus_sched_default"
    )

    RecordingStudioStripe::ChangePlan.call(root_recording: @root, price: starter)

    assert_equal [{ from_subscription: "sub_sched_default" }], client.schedule_creates
    assert_empty client.subscription_updates
    subscription = @workspace.billing.line(:studio).subscription.reload
    assert_equal pro.id, subscription.price_id
    assert_equal starter.id, subscription.scheduled_price_id
  end

  test "immediate timing switches the Stripe price now and cancels now" do
    use_immediate_studio
    client = use_stripe_client
    pro = @pro.monthly_price
    starter = @starter.monthly_price
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: pro,
      stripe_subscription_id: "sub_now",
      stripe_customer_id: "cus_now"
    )

    RecordingStudioStripe::ChangePlan.call(root_recording: @root, price: starter)

    assert_empty client.schedule_creates
    assert_equal "create_prorations", client.subscription_updates.last[:proration_behavior]
    assert_equal starter.stripe_id, client.subscription_updates.last[:items].first[:price]
    subscription = @workspace.billing.line(:studio).subscription.reload
    assert_equal pro.id, subscription.price_id
    assert_nil subscription.scheduled_price_id

    RecordingStudioStripe::CancelSubscription.call(root_recording: @root, subscription_type: "studio")

    assert_equal ["sub_now"], client.subscription_cancels
    assert_equal "active", subscription.reload.status
    refute subscription.cancel_at_period_end
  end

  test "confirmation pages state period-end timing by default and today when immediate" do
    pro = @pro.monthly_price
    starter = @starter.monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)

    get recording_studio_stripe.subscription_change_path, params: { price_id: starter.id }

    assert_response :success
    assert_includes response.body, "Downgrade to Starter?"
    assert_includes response.body, "Starts on"
    refute_includes response.body, "Switches today"

    get recording_studio_stripe.subscription_cancel_confirm_path

    assert_response :success
    assert_includes response.body, "You keep it until"
    assert_includes response.body, "Cancel at period end"
    refute_includes response.body, "Cancel now"

    use_immediate_studio

    get recording_studio_stripe.subscription_change_path, params: { price_id: starter.id }

    assert_response :success
    assert_includes response.body, "Switches today. Unused time is credited."
    refute_includes response.body, "Starts on"

    get recording_studio_stripe.subscription_cancel_confirm_path

    assert_response :success
    assert_includes response.body, "This ends today."
    assert_includes response.body, "Cancel now"
    refute_includes response.body, "Cancel at period end"
  end

  test "admin can change plan and edit and view cannot" do
    pro = @pro.monthly_price
    starter = @starter.monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)

    patch recording_studio_stripe.subscription_path, params: { price_id: starter.id }

    assert_redirected_to recording_studio_stripe.root_path
    assert_equal starter.id, @workspace.billing.line(:studio).subscription.reload.scheduled_price_id

    editor = user_with_role("editor-plan@example.com", :edit)
    sign_in editor
    switch_to_root!(@root)

    patch recording_studio_stripe.subscription_path, params: { price_id: pro.id }

    assert_response :forbidden

    viewer = user_with_role("viewer-plan@example.com", :view)
    sign_in viewer
    switch_to_root!(@root)

    patch recording_studio_stripe.subscription_path, params: { price_id: pro.id }

    assert_response :forbidden
    assert_equal starter.id, @workspace.billing.line(:studio).subscription.reload.scheduled_price_id
  end

  test "a scheduled downgrade emits once when the renewal webhook applies it" do
    subscription = subscribe!("sub_renew", @pro.monthly_price)
    subscription.update!(scheduled_price: @starter.monthly_price)

    events = capture do
      post_price("evt_renew", "sub_renew", @starter.monthly_price)
    end

    assert_equal 1, events.size
    payload = events.first.payload
    assert_equal EVENT, events.first.name
    assert_equal 1, payload[:schema_version]
    assert_equal @root.id, payload[:root_recording_id]
    assert_equal "studio", payload[:subscription_type]
    assert_equal @pro.id, payload[:old_product_id]
    assert_equal "Pro", payload[:old_product_name]
    assert_equal @starter.id, payload[:new_product_id]
    assert_equal "Starter", payload[:new_product_name]
    assert_equal ["generate_image"], payload[:paywalls_lost]
    assert_equal [
      { name: "max_file_bytes", from: 2.gigabytes, to: 50.megabytes },
      { name: "press_kits", from: 10, to: 3 }
    ], payload[:limits_lowered]
    assert_equal "downgrade", payload[:reason]
    assert_equal "at_period_end", payload[:timing]
    assert_equal Time.zone.at(CREATED).utc.iso8601, payload[:effective_at]
    assert_equal @starter.monthly_price.id, subscription.reload.price_id

    again = capture { post_price("evt_renew", "sub_renew", @starter.monthly_price) }
    assert_empty again
    assert_equal 1, RecordingStudioStripe::DomainEvent.where(name: "plan_downgraded").count

    replayed = capture do
      replay("evt_renew")
      replay("evt_renew")
    end
    assert_empty replayed

    stored = RecordingStudioStripe::DomainEvent.find_by!(idempotency_key: "plan_downgraded/evt_renew")
    stored.destroy!
    rebuilt = capture { replay("evt_renew") }
    assert_equal 1, rebuilt.size
    assert_equal ["generate_image"], rebuilt.first.payload[:paywalls_lost]
    assert_equal 1, RecordingStudioStripe::DomainEvent.where(idempotency_key: "plan_downgraded/evt_renew").count
  end

  test "an immediate downgrade emits when the webhook applies the new price" do
    subscribe!("sub_immediate", @pro.monthly_price)

    events = capture { post_price("evt_immediate", "sub_immediate", @starter.monthly_price) }

    assert_equal 1, events.size
    assert_equal "immediately", events.first.payload[:timing]
    assert_equal "downgrade", events.first.payload[:reason]
    assert_equal ["generate_image"], events.first.payload[:paywalls_lost]
    assert_equal @starter.id, events.first.payload[:new_product_id]
  end

  test "cancel at period end emits every lost paywall and limit against an empty plan" do
    subscription = subscribe!("sub_cancel_end", @pro.monthly_price)
    subscription.update!(cancel_at_period_end: true)

    events = capture { post_deleted("evt_cancel_end", "sub_cancel_end") }

    assert_equal 1, events.size
    payload = events.first.payload
    assert_nil payload[:new_product_id]
    assert_nil payload[:new_product_name]
    assert_equal "canceled", payload[:reason]
    assert_equal "at_period_end", payload[:timing]
    assert_equal ["generate_image"], payload[:paywalls_lost]
    assert_equal [
      { name: "max_file_bytes", from: 2.gigabytes, to: nil },
      { name: "press_kits", from: 10, to: nil }
    ], payload[:limits_lowered]
    assert_equal "canceled", subscription.reload.status
  end

  test "Stripe ending a past due subscription after a failed payment emits a cancel" do
    subscribe!("sub_dunning", @pro.monthly_price)
    quiet = capture do
      post "/webhooks/stripe",
           params: stripe_event(
             "evt_dunning_fail",
             "invoice.payment_failed",
             {
               "id" => "in_dunning",
               "customer" => "cus_sub_dunning",
               "parent" => {
                 "type" => "subscription_details",
                 "subscription_details" => { "subscription" => "sub_dunning" }
               }
             }
           ),
           as: :json
      assert_response :success
    end
    assert_empty quiet
    assert_equal "past_due", RecordingStudioStripe::Subscription.find_by!(stripe_id: "sub_dunning").status

    events = capture { post_deleted("evt_dunning_end", "sub_dunning") }

    assert_equal 1, events.size
    assert_equal "canceled", events.first.payload[:reason]
    assert_equal "immediately", events.first.payload[:timing]
    assert_equal ["generate_image"], events.first.payload[:paywalls_lost]
  end

  test "an upgrade and a no-loss change emit nothing" do
    subscribe!("sub_upgrade", @starter.monthly_price)
    upgrade = capture { post_price("evt_upgrade", "sub_upgrade", @pro.monthly_price) }
    assert_empty upgrade

    yearly = @pro.annual_price
    same_product = capture { post_price("evt_interval", "sub_upgrade", yearly) }
    assert_empty same_product

    @starter.assign_paywalls(%w[generate_image])
    @starter.assign_limits("press_kits" => 10, "max_file_bytes" => 2.gigabytes)
    @starter.save!
    no_loss = capture { post_price("evt_same_entitlements", "sub_upgrade", @starter.monthly_price) }
    assert_empty no_loss
    assert_equal 0, RecordingStudioStripe::DomainEvent.where(name: "plan_downgraded").count
  end

  test "a higher price that drops a limit still emits that loss" do
    subscribe!("sub_team", @pro.monthly_price)

    events = capture { post_price("evt_team", "sub_team", @team.monthly_price) }

    assert_equal 1, events.size
    assert_equal [], events.first.payload[:paywalls_lost]
    assert_equal [{ name: "max_file_bytes", from: 2.gigabytes, to: nil }], events.first.payload[:limits_lowered]
    assert_equal "downgrade", events.first.payload[:reason]
  end

  test "undoing a pending cancel or downgrade emits nothing" do
    subscription = subscribe!("sub_undo", @pro.monthly_price)
    subscription.update!(cancel_at_period_end: true, scheduled_price: @starter.monthly_price)

    RecordingStudioStripe::ResumeSubscription.call(root_recording: @root, subscription_type: "studio")
    RecordingStudioStripe::ClearScheduledChange.call(root_recording: @root, subscription_type: "studio")
    assert_equal 0, RecordingStudioStripe::DomainEvent.where(name: "plan_downgraded").count

    subscription.update!(cancel_at_period_end: true, scheduled_price: @starter.monthly_price)
    events = capture { post_price("evt_undo", "sub_undo", @pro.monthly_price, cancel_at_period_end: false) }

    assert_empty events
    assert_equal @pro.monthly_price.id, subscription.reload.price_id
  end

  test "a zero invoice still does not emit invoice_paid" do
    subscribe!("sub_zero", @pro.monthly_price)
    events = capture_named(RecordingStudioStripe::DomainEvents::INVOICE_PAID) do
      post "/webhooks/stripe",
           params: stripe_event(
             "evt_zero_downgrade",
             "invoice.paid",
             {
               "id" => "in_zero_downgrade",
               "amount_paid" => 0,
               "currency" => "usd",
               "customer" => "cus_sub_zero",
               "parent" => {
                 "type" => "subscription_details",
                 "subscription_details" => { "subscription" => "sub_zero" }
               },
               "lines" => { "data" => [{ "amount" => 0, "price" => { "id" => @pro.monthly_price.stripe_id } }], "has_more" => false }
             }
           ),
           as: :json
      assert_response :success
    end

    assert_empty events
    assert_equal 0, RecordingStudioStripe::DomainEvent.where(name: "invoice_paid").count
  end

  private

  def use_stripe_client
    client = RecordingStudioStripe::Testing::Client.new
    RecordingStudioStripe.configuration.client = client
    client
  end

  def use_immediate_studio
    types = @previous_types.to_h.stringify_keys
    studio = types.fetch("studio").to_h.stringify_keys.merge("downgrade_timing" => "immediately")
    RecordingStudioStripe.configuration.subscription_types = types.merge("studio" => studio)
  end

  def user_with_role(email, role)
    user = User.find_or_create_by!(email: email) do |record|
      record.password = "Password"
      record.password_confirmation = "Password"
    end
    grant_owner_access!(recording: @root, actor: user, role: role)
    sign_out @user
    user
  end

  def subscribe!(stripe_id, price)
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: price,
      stripe_subscription_id: stripe_id,
      stripe_customer_id: "cus_#{stripe_id}",
      status: "active"
    )
  end

  def post_price(event_id, stripe_id, price, cancel_at_period_end: false)
    post "/webhooks/stripe",
         params: stripe_event(
           event_id,
           "customer.subscription.updated",
           subscription_object(stripe_id, price, "active", cancel_at_period_end)
         ),
         as: :json
    assert_response :success
  end

  def post_deleted(event_id, stripe_id)
    price = RecordingStudioStripe::Subscription.find_by!(stripe_id: stripe_id).price
    post "/webhooks/stripe",
         params: stripe_event(
           event_id,
           "customer.subscription.deleted",
           subscription_object(stripe_id, price, "canceled", false)
         ),
         as: :json
    assert_response :success
  end

  def subscription_object(stripe_id, price, status, cancel_at_period_end)
    {
      "id" => stripe_id,
      "customer" => "cus_#{stripe_id}",
      "status" => status,
      "cancel_at_period_end" => cancel_at_period_end,
      "metadata" => { "root_recording_id" => @root.id.to_s },
      "items" => {
        "data" => [
          {
            "id" => "si_#{stripe_id}",
            "price" => { "id" => price.stripe_id },
            "current_period_start" => CREATED,
            "current_period_end" => CREATED + 30.days.to_i
          }
        ]
      }
    }
  end

  def stripe_event(id, type, object)
    { "id" => id, "object" => "event", "type" => type, "created" => CREATED, "data" => { "object" => object } }
  end

  def replay(stripe_id)
    RecordingStudioStripe::ProcessWebhook.replay(
      RecordingStudioStripe::WebhookEvent.find_by!(stripe_id: stripe_id)
    )
  end

  def capture(&block)
    capture_named(EVENT, &block)
  end

  def capture_named(name)
    found = []
    subscriber = ActiveSupport::Notifications.subscribe(name) do |*args|
      found << ActiveSupport::Notifications::Event.new(*args)
    end
    yield
    found
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
