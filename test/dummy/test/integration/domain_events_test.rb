# frozen_string_literal: true

require "test_helper"

class DomainEventsTest < ActionDispatch::IntegrationTest
  TRIAL = RecordingStudioStripe::DomainEvents::TRIAL_STARTED
  INVOICE = RecordingStudioStripe::DomainEvents::INVOICE_PAID

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    @root = RecordingStudio.root_recording_for(@workspace)
    @pro = RecordingStudioStripe::Product.find_by!(name: "Pro")
    @price = @pro.monthly_price
    @fee = @pro.trial.fee_price
  end

  test "trial_started fires once after commit when a subscription is first stored as trialing" do
    occurred_at = Time.zone.at(1_700_000_000)
    subscription_id = nil

    events = capture(TRIAL) do
      ApplicationRecord.transaction do
        post_subscription("evt_trial_once", "sub_trial_once", status: "trialing")
        assert_empty _events
      end
    end

    assert_equal 1, events.size
    payload = events.first.payload
    subscription = RecordingStudioStripe::Subscription.find_by!(stripe_id: "sub_trial_once")
    subscription_id = subscription.id
    assert_equal TRIAL, events.first.name
    assert_equal 1, payload[:schema_version]
    assert_equal occurred_at, payload[:occurred_at]
    assert_equal subscription.id, payload[:subscription_id]
    assert_equal subscription.customer_id, payload[:customer_id]
    assert_equal @root.id, payload[:root_recording_id]
    refute_equal subscription.id, payload[:id]
    domain_event = RecordingStudioStripe::DomainEvent.find(payload[:id])
    assert_equal subscription.id, domain_event.subscription_id
    assert_predicate domain_event, :published_at

    more = capture(TRIAL) do
      post_subscription("evt_trial_again", "sub_trial_once", status: "trialing", created: 1_700_000_100)
    end
    assert_empty more
    assert_equal subscription_id, subscription.reload.id

    duplicate = capture(TRIAL) do
      post_subscription("evt_trial_once", "sub_trial_once", status: "trialing")
    end
    assert_empty duplicate

    replay = capture(TRIAL) do
      replay_webhook("evt_trial_once")
      replay_webhook("evt_trial_once")
    end
    assert_empty replay
    assert_equal domain_event.id, domain_event.reload.id
  end

  test "trial_started fires when an existing subscription first becomes trialing" do
    subscription = RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: @price,
      stripe_subscription_id: "sub_becomes_trial",
      stripe_customer_id: "cus_becomes_trial",
      status: "active"
    )

    events = capture(TRIAL) do
      subscription.update!(status: "trialing")
      subscription.update!(cancel_at_period_end: true)
    end

    assert_equal 1, events.size
    assert_equal subscription.id, events.first.payload[:subscription_id]
    assert_equal subscription.customer_id, events.first.payload[:customer_id]
  end

  test "a rolled back trial does not emit" do
    events = capture(TRIAL) do
      ApplicationRecord.transaction do
        RecordingStudioStripe::ApplySubscription.call(
          root_recording: @root,
          price: @price,
          stripe_subscription_id: "sub_rollback_trial",
          stripe_customer_id: "cus_rollback_trial",
          status: "trialing"
        )
        raise ActiveRecord::Rollback
      end
    end

    assert_empty events
    refute RecordingStudioStripe::Subscription.exists?(stripe_id: "sub_rollback_trial")
    assert_equal 0, RecordingStudioStripe::DomainEvent.where(name: "trial_started").count
  end

  test "replay emits an unpublished trial_started once and keeps its id" do
    capture(TRIAL) { post_subscription("evt_trial_crash", "sub_trial_crash", status: "trialing") }
    webhook = RecordingStudioStripe::WebhookEvent.find_by!(stripe_id: "evt_trial_crash")
    domain_event = RecordingStudioStripe::DomainEvent.find_by!(webhook_event_id: webhook.id)
    domain_event.update_column(:published_at, nil)
    subscription_id = domain_event.subscription_id

    events = capture(TRIAL) do
      RecordingStudioStripe::ProcessWebhook.replay(webhook)
      RecordingStudioStripe::ProcessWebhook.replay(webhook)
    end

    assert_equal [domain_event.id], events.map { |event| event.payload[:id] }
    assert_equal subscription_id, domain_event.reload.subscription_id
    assert_predicate domain_event, :published_at
  end

  test "replay rebuilds trial_started from the stored webhook when the event row is gone" do
    capture(TRIAL) { post_subscription("evt_trial_rebuild", "sub_trial_rebuild", status: "trialing") }
    webhook = RecordingStudioStripe::WebhookEvent.find_by!(stripe_id: "evt_trial_rebuild")
    subscription = RecordingStudioStripe::Subscription.find_by!(stripe_id: "sub_trial_rebuild")
    RecordingStudioStripe::DomainEvent.delete_all

    events = capture(TRIAL) { RecordingStudioStripe::ProcessWebhook.replay(webhook) }

    assert_equal 1, events.size
    assert_equal subscription.id, events.first.payload[:subscription_id]
    assert_equal subscription.reload.id, subscription.id
    assert_equal "trialing", webhook.payload["subscription_status"]
    refute webhook.payload.key?("data")
  end

  test "invoice_paid carries amount currency and first_payment, and a trial fee does not count" do
    subscription = subscribe!("sub_invoice_events", "cus_invoice_events")
    occurred_at = Time.zone.at(1_700_000_000)

    fee_events = capture(INVOICE) { post_invoice("evt_fee", "in_fee", "sub_invoice_events", amount: 100, lines: fee_lines) }
    assert_empty fee_events
    assert_equal "trialing", subscription.reload.status

    subscription.update!(status: "past_due")
    fee_while_past_due = capture(INVOICE) do
      post_invoice("evt_fee_past_due", "in_fee_past_due", "sub_invoice_events", amount: 100, lines: fee_lines,
                                                                                 created: 1_700_000_050)
    end
    assert_empty fee_while_past_due
    assert_equal "active", subscription.reload.status
    stored_fee = RecordingStudioStripe::WebhookEvent.find_by!(stripe_id: "evt_fee").payload["invoice"]
    assert stored_fee["trial_fee"]
    assert_equal 100, stored_fee["amount_paid"]
    assert_equal "usd", stored_fee["currency"]

    first = capture(INVOICE) do
      post_invoice("evt_first", "in_first", "sub_invoice_events", amount: 2900, lines: plan_lines)
    end
    assert_equal 1, first.size
    payload = first.first.payload
    assert_equal INVOICE, first.first.name
    assert_equal 1, payload[:schema_version]
    assert_equal occurred_at, payload[:occurred_at]
    assert_equal 2900, payload[:amount]
    assert_equal "usd", payload[:currency]
    assert_equal "in_first", payload[:invoice_id]
    assert payload[:first_payment]
    assert_equal subscription.id, payload[:subscription_id]
    assert_equal subscription.customer_id, payload[:customer_id]
    assert_equal @root.id, payload[:root_recording_id]
    refute_equal subscription.id, payload[:id]

    second = capture(INVOICE) do
      post_invoice("evt_second", "in_second", "sub_invoice_events", amount: 2900, lines: plan_lines, created: 1_700_086_400)
    end
    assert_equal 1, second.size
    refute second.first.payload[:first_payment]
    assert_equal 2900, second.first.payload[:amount]

    duplicate = capture(INVOICE) do
      post_invoice("evt_first", "in_first", "sub_invoice_events", amount: 2900, lines: plan_lines)
    end
    assert_empty duplicate
    assert_equal 2, RecordingStudioStripe::DomainEvent.where(name: "invoice_paid").count
  end

  test "invoice paid still clears past_due and the event fires after that transaction commits" do
    subscription = subscribe!("sub_past_due", "cus_past_due", status: "active")
    subscription.update!(status: "past_due")
    baseline = ApplicationRecord.connection.open_transactions
    open_during = nil

    events = capture(INVOICE) do
      subscriber = ActiveSupport::Notifications.subscribe(INVOICE) do
        open_during = ApplicationRecord.connection.open_transactions
      end
      post_invoice("evt_recover", "in_recover", "sub_past_due", amount: 2900, lines: plan_lines)
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    assert_equal "active", subscription.reload.status
    assert_equal 1, events.size
    assert events.first.payload[:first_payment]
    assert_equal baseline, open_during
  end

  test "replay of a paid invoice does not double emit, and an unpublished row emits once" do
    subscribe!("sub_replay_invoice", "cus_replay_invoice")
    capture(INVOICE) { post_invoice("evt_paid_replay", "in_paid_replay", "sub_replay_invoice", amount: 2900, lines: plan_lines) }
    webhook = RecordingStudioStripe::WebhookEvent.find_by!(stripe_id: "evt_paid_replay")
    domain_event = RecordingStudioStripe::DomainEvent.find_by!(idempotency_key: "invoice_paid/in_paid_replay")

    quiet = capture(INVOICE) { RecordingStudioStripe::ProcessWebhook.replay(webhook) }
    assert_empty quiet

    domain_event.update_column(:published_at, nil)
    events = capture(INVOICE) do
      RecordingStudioStripe::ProcessWebhook.replay(webhook)
      RecordingStudioStripe::ProcessWebhook.replay(webhook)
    end

    assert_equal [domain_event.id], events.map { |event| event.payload[:id] }
    assert_equal 2900, events.first.payload[:amount]
    assert events.first.payload[:first_payment]
    assert_equal domain_event.id, domain_event.reload.id
  end

  test "replay rebuilds invoice_paid from the stored snapshot without a second first payment" do
    subscribe!("sub_rebuild_invoice", "cus_rebuild_invoice")
    capture(INVOICE) do
      post_invoice("evt_rebuild_fee", "in_rebuild_fee", "sub_rebuild_invoice", amount: 100, lines: fee_lines)
      post_invoice("evt_rebuild_paid", "in_rebuild_paid", "sub_rebuild_invoice", amount: 4200, lines: plan_lines(amount: 4200))
    end
    webhook = RecordingStudioStripe::WebhookEvent.find_by!(stripe_id: "evt_rebuild_paid")
    subscription = RecordingStudioStripe::Subscription.find_by!(stripe_id: "sub_rebuild_invoice")
    RecordingStudioStripe::DomainEvent.where(name: "invoice_paid").delete_all

    fee_replay = capture(INVOICE) do
      RecordingStudioStripe::ProcessWebhook.replay(
        RecordingStudioStripe::WebhookEvent.find_by!(stripe_id: "evt_rebuild_fee")
      )
    end
    paid_replay = capture(INVOICE) { RecordingStudioStripe::ProcessWebhook.replay(webhook) }

    assert_empty fee_replay
    assert_equal 1, paid_replay.size
    assert_equal 4200, paid_replay.first.payload[:amount]
    assert_equal "usd", paid_replay.first.payload[:currency]
    assert_equal "in_rebuild_paid", paid_replay.first.payload[:invoice_id]
    assert paid_replay.first.payload[:first_payment]
    assert_equal subscription.id, paid_replay.first.payload[:subscription_id]
    assert_equal subscription.id, subscription.reload.id
  end

  private

  def capture(name)
    found = []
    subscriber = ActiveSupport::Notifications.subscribe(name) do |*args|
      found << ActiveSupport::Notifications::Event.new(*args)
    end
    @_events = found
    yield
    found
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def _events
    @_events || []
  end

  def subscribe!(stripe_id, customer_id, status: "trialing")
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: @price,
      stripe_subscription_id: stripe_id,
      stripe_customer_id: customer_id,
      status: status
    )
  end

  def post_subscription(event_id, stripe_id, status:, created: 1_700_000_000)
    post "/webhooks/stripe",
         params: stripe_event(
           event_id,
           "customer.subscription.created",
           {
            "id" => stripe_id,
            "customer" => "cus_#{stripe_id}",
            "status" => status,
            "cancel_at_period_end" => false,
             "metadata" => { "root_recording_id" => @root.id.to_s },
             "items" => {
               "data" => [
                 {
                   "id" => "si_#{stripe_id}",
                   "price" => { "id" => @price.stripe_id },
                   "current_period_start" => created,
                   "current_period_end" => created + 14.days.to_i
                 }
               ]
             }
           },
           created: created
         ),
         as: :json
    assert_response :success
  end

  def post_invoice(event_id, invoice_id, stripe_subscription_id, amount:, lines:, created: 1_700_000_000)
    post "/webhooks/stripe",
         params: stripe_event(
           event_id,
           "invoice.paid",
           {
             "id" => invoice_id,
             "amount_paid" => amount,
             "currency" => "usd",
             "customer" => "cus_#{stripe_subscription_id}",
             "parent" => {
               "type" => "subscription_details",
               "subscription_details" => { "subscription" => stripe_subscription_id }
             },
             "lines" => { "data" => lines }
           },
           created: created
         ),
         as: :json
    assert_response :success
  end

  def fee_lines
    [
      { "amount" => 100, "price" => { "id" => @fee.stripe_id } },
      { "amount" => 0, "price" => { "id" => @price.stripe_id } }
    ]
  end

  def plan_lines(amount: 2900)
    [{ "amount" => amount, "pricing" => { "price_details" => { "price" => @price.stripe_id } } }]
  end

  def replay_webhook(stripe_id)
    RecordingStudioStripe::ProcessWebhook.replay(
      RecordingStudioStripe::WebhookEvent.find_by!(stripe_id: stripe_id)
    )
  end

  def stripe_event(id, type, object, created:)
    { "id" => id, "object" => "event", "type" => type, "created" => created, "data" => { "object" => object } }
  end
end
