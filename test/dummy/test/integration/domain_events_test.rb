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

  test "a zero amount invoice does not emit and the next positive invoice is first_payment" do
    subscription = subscribe!("sub_zero", "cus_zero", status: "past_due")

    zero = capture(INVOICE) do
      post_invoice("evt_zero", "in_zero", "sub_zero", amount: 0, lines: plan_lines(amount: 0),
                                                      billing_reason: "subscription_create")
    end
    assert_empty zero
    assert_equal "active", subscription.reload.status
    stored = RecordingStudioStripe::WebhookEvent.find_by!(stripe_id: "evt_zero").payload["invoice"]
    assert_equal 0, stored["amount_paid"]
    assert_equal "subscription_create", stored["billing_reason"]
    refute RecordingStudioStripe::DomainEvent.exists?(idempotency_key: "invoice_paid/in_zero")

    paid = capture(INVOICE) do
      post_invoice("evt_zero_real", "in_zero_real", "sub_zero", amount: 2900, lines: plan_lines,
                                                                 billing_reason: "subscription_cycle")
    end
    assert_equal 1, paid.size
    assert paid.first.payload[:first_payment]
    assert_equal 2900, paid.first.payload[:amount]
  end

  test "a blank invoice id does not emit" do
    subscribe!("sub_blank_invoice", "cus_blank_invoice", status: "active")

    events = capture(INVOICE) do
      post_invoice("evt_blank_invoice", "", "sub_blank_invoice", amount: 2900, lines: plan_lines)
    end

    assert_empty events
    assert_equal 0, RecordingStudioStripe::DomainEvent.where(name: "invoice_paid").count
  end

  test "an unknown price is deferred and a priceless line still emits" do
    subscribe!("sub_lines", "cus_lines", status: "active")

    post_invoice("evt_unknown_price", "in_unknown_price", "sub_lines", amount: 100,
                                                                       lines: [{ "amount" => 100, "price" => { "id" => "price_missing" } }],
                                                                       success: :service_unavailable)
    refute RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_unknown_price")
    assert_equal 0, RecordingStudioStripe::DomainEvent.where(name: "invoice_paid").count

    events = capture(INVOICE) do
      post_invoice("evt_priceless", "in_priceless", "sub_lines", amount: 500,
                                                                 lines: [{ "amount" => 500 }],
                                                                 billing_reason: "subscription_create")
    end
    assert_equal 1, events.size
    assert_equal 500, events.first.payload[:amount]
    assert events.first.payload[:first_payment]
    snapshot = RecordingStudioStripe::WebhookEvent.find_by!(stripe_id: "evt_priceless").payload["invoice"]
    refute snapshot["trial_fee"]
    assert_equal "", snapshot["lines"].first["price_id"]
  end

  test "trial fee kind matching ignores case" do
    subscribe!("sub_kind_case", "cus_kind_case", status: "active")
    @fee.update!(metadata: @fee.metadata.to_h.merge("kind" => "TRIAL_FEE"))

    events = capture(INVOICE) do
      post_invoice("evt_kind_case", "in_kind_case", "sub_kind_case", amount: 100, lines: fee_lines)
    end

    assert_empty events
    assert RecordingStudioStripe::WebhookEvent.find_by!(stripe_id: "evt_kind_case").payload["invoice"]["trial_fee"]
  end

  test "a subscription created before payments were tracked does not report a renewal as first_payment" do
    existing = subscribe!("sub_before_upgrade", "cus_before_upgrade", status: "active")
    existing.update!(metadata: existing.metadata.to_h.except("payments_tracked"))

    renewal = capture(INVOICE) do
      post_invoice("evt_old_renewal", "in_old_renewal", "sub_before_upgrade", amount: 2900, lines: plan_lines,
                                                                              billing_reason: "subscription_cycle")
    end
    refute renewal.first.payload[:first_payment]

    created = capture(INVOICE) do
      post_invoice("evt_old_create", "in_old_create", "sub_before_upgrade", amount: 2900, lines: plan_lines,
                                                                            billing_reason: "subscription_create",
                                                                            created: 1_700_000_010)
    end
    assert created.first.payload[:first_payment]

    tracked_root = RecordingStudio.root_recording_for(Workspace.create!(name: "Upgrade Workspace"))
    tracked = RecordingStudioStripe::ApplySubscription.call(
      root_recording: tracked_root,
      price: @price,
      stripe_subscription_id: "sub_after_upgrade",
      stripe_customer_id: "cus_after_upgrade",
      status: "active"
    )
    assert_equal true, tracked.metadata["payments_tracked"]
    zero = capture(INVOICE) do
      post_invoice("evt_tracked_zero", "in_tracked_zero", "sub_after_upgrade", amount: 0, lines: plan_lines(amount: 0),
                                                                               billing_reason: "subscription_create")
    end
    assert_empty zero
    first_real = capture(INVOICE) do
      post_invoice("evt_tracked_real", "in_tracked_real", "sub_after_upgrade", amount: 2900, lines: plan_lines,
                                                                               billing_reason: "subscription_cycle")
    end
    assert first_real.first.payload[:first_payment]
  end

  test "invoice_paid still emits when the subscription is canceled" do
    subscription = subscribe!("sub_canceled_paid", "cus_canceled_paid", status: "active")
    subscription.update!(status: "canceled")

    events = capture(INVOICE) do
      post_invoice("evt_canceled_paid", "in_canceled_paid", "sub_canceled_paid", amount: 2900, lines: plan_lines,
                                                                                 billing_reason: "subscription_cycle")
    end

    assert_equal 1, events.size
    assert_equal "canceled", subscription.reload.status
  end

  test "a raising subscriber leaves the event unpublished and the sweep retries" do
    subscribe!("sub_raiser", "cus_raiser", status: "active")
    recorder = ErrorRecorder.new
    Rails.error.subscribe(recorder)
    raiser = ActiveSupport::Notifications.subscribe(INVOICE) { raise "subscriber blew up" }

    post_invoice("evt_raiser", "in_raiser", "sub_raiser", amount: 2900, lines: plan_lines,
                                                          billing_reason: "subscription_create")

    domain_event = RecordingStudioStripe::DomainEvent.find_by!(idempotency_key: "invoice_paid/in_raiser")
    assert_nil domain_event.published_at
    assert_equal 1, recorder.errors.size
    assert_equal "subscriber blew up", recorder.errors.first.message
    assert_equal [true], recorder.handled

    ActiveSupport::Notifications.unsubscribe(raiser)
    domain_event.update_column(:created_at, 10.minutes.ago)
    retried = capture(INVOICE) { RecordingStudioStripe::PublishPendingDomainEventsJob.perform_now(300) }

    assert_equal [domain_event.id], retried.map { |event| event.payload[:id] }
    assert_predicate domain_event.reload, :published_at
  ensure
    ActiveSupport::Notifications.unsubscribe(raiser) if raiser
    Rails.error.unsubscribe(recorder) if recorder
  end

  test "the pending rake task publishes an old unpublished event" do
    subscribe!("sub_rake", "cus_rake", status: "active")
    capture(INVOICE) do
      post_invoice("evt_rake", "in_rake", "sub_rake", amount: 1500, lines: plan_lines(amount: 1500))
    end
    domain_event = RecordingStudioStripe::DomainEvent.find_by!(idempotency_key: "invoice_paid/in_rake")
    domain_event.update_columns(published_at: nil, created_at: 10.minutes.ago)
    Rails.application.load_tasks
    previous = ENV.fetch("OLDER_THAN_SECONDS", nil)
    ENV["OLDER_THAN_SECONDS"] = "60"

    events = capture(INVOICE) do
      Rake::Task["recording_studio_stripe:publish_pending_domain_events"].reenable
      Rake::Task["recording_studio_stripe:publish_pending_domain_events"].invoke
    end

    assert_equal [domain_event.id], events.map { |event| event.payload[:id] }
    assert_predicate domain_event.reload, :published_at
  ensure
    if previous
      ENV["OLDER_THAN_SECONDS"] = previous
    else
      ENV.delete("OLDER_THAN_SECONDS")
    end
  end

  test "replay inside an open transaction emits after that transaction commits" do
    subscribe!("sub_outer", "cus_outer", status: "active")
    capture(INVOICE) do
      post_invoice("evt_outer", "in_outer", "sub_outer", amount: 2900, lines: plan_lines)
    end
    webhook = RecordingStudioStripe::WebhookEvent.find_by!(stripe_id: "evt_outer")
    domain_event = RecordingStudioStripe::DomainEvent.find_by!(idempotency_key: "invoice_paid/in_outer")
    domain_event.update_column(:published_at, nil)
    seen_inside = nil

    events = capture(INVOICE) do
      ApplicationRecord.transaction do
        RecordingStudioStripe::ProcessWebhook.replay(webhook)
        seen_inside = _events.size
      end
    end

    assert_equal 0, seen_inside
    assert_equal [domain_event.id], events.map { |event| event.payload[:id] }
    assert_predicate domain_event.reload, :published_at
  end

  test "the same invoice id on a second webhook does not poison the transaction" do
    subscribe!("sub_same_invoice", "cus_same_invoice", status: "active")
    capture(INVOICE) do
      post_invoice("evt_same_a", "in_same", "sub_same_invoice", amount: 2900, lines: plan_lines)
      post_invoice("evt_same_b", "in_same", "sub_same_invoice", amount: 2900, lines: plan_lines, created: 1_700_000_020)
    end

    assert_equal 1, RecordingStudioStripe::DomainEvent.where(idempotency_key: "invoice_paid/in_same").count
    assert RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_same_b")
  end

  test "destroying a customer deletes its domain events" do
    subscription = subscribe!("sub_destroy_customer", "cus_destroy_customer", status: "active")
    capture(INVOICE) do
      post_invoice("evt_destroy_customer", "in_destroy_customer", "sub_destroy_customer", amount: 2900, lines: plan_lines)
    end
    customer = subscription.customer
    customer_id = customer.id

    customer.destroy!

    refute RecordingStudioStripe::DomainEvent.exists?(customer_id: customer_id)
    refute RecordingStudioStripe::Subscription.exists?(id: subscription.id)
  end

  test "a missing domain events table does not raise when a subscription is saved" do
    singleton = RecordingStudioStripe::DomainEvents.singleton_class
    singleton.alias_method(:events_table_without_stub?, :events_table?)
    singleton.define_method(:events_table?) { false }
    events = capture(TRIAL) do
      subscribe!("sub_no_table", "cus_no_table", status: "trialing")
    end

    assert_empty events
    assert RecordingStudioStripe::Subscription.exists?(stripe_id: "sub_no_table")
    assert_equal 0, RecordingStudioStripe::DomainEvent.where(name: "trial_started").count
  ensure
    if singleton&.method_defined?(:events_table_without_stub?)
      singleton.alias_method(:events_table?, :events_table_without_stub?)
      singleton.remove_method(:events_table_without_stub?)
    end
  end

  test "checkout that only has a subscription id stores the retrieved status" do
    price = @price
    configuration = RecordingStudioStripe.configuration
    previous_client = configuration.client
    previous_secret = configuration.webhook_secret
    subscription = Stripe::StripeObject.construct_from(
      "id" => "sub_retrieved_checkout",
      "status" => "trialing",
      "customer" => "cus_retrieved_checkout",
      "cancel_at_period_end" => false,
      "items" => {
        "data" => [
          {
            "id" => "si_retrieved_checkout",
            "price" => { "id" => price.stripe_id },
            "current_period_start" => 1_700_000_000,
            "current_period_end" => 1_700_000_000 + 14.days.to_i
          }
        ]
      }
    )
    client = RetrievedSubscriptionClient.new(subscription)
    configuration.client = client
    configuration.webhook_secret = "whsec_domain_events"
    payload = stripe_event(
      "evt_retrieved_checkout",
      "checkout.session.completed",
      {
        "id" => "cs_retrieved",
        "mode" => "subscription",
        "payment_status" => "paid",
        "subscription" => "sub_retrieved_checkout",
        "customer" => "cus_retrieved_checkout",
        "client_reference_id" => @root.id.to_s,
        "metadata" => {
          "root_recording_id" => @root.id.to_s,
          "price_id" => price.stripe_id
        }
      },
      created: 1_700_000_000
    ).to_json
    signature = signed_header(payload, configuration.webhook_secret)

    events = capture(TRIAL) do
      post "/webhooks/stripe",
           params: payload,
           headers: { "CONTENT_TYPE" => "application/json", "HTTP_STRIPE_SIGNATURE" => signature }
    end

    assert_response :success
    webhook = RecordingStudioStripe::WebhookEvent.find_by!(stripe_id: "evt_retrieved_checkout")
    assert_equal "trialing", webhook.payload["subscription_status"]
    assert_equal "sub_retrieved_checkout", webhook.payload["stripe_subscription_id"]
    assert_equal 1, events.size
    assert_equal "trialing", RecordingStudioStripe::Subscription.find_by!(stripe_id: "sub_retrieved_checkout").status
  ensure
    configuration.client = previous_client
    configuration.webhook_secret = previous_secret
  end

  test "invoice snapshot records lines_has_more" do
    subscribe!("sub_has_more", "cus_has_more", status: "active")
    post_invoice(
      "evt_has_more",
      "in_has_more",
      "sub_has_more",
      amount: 2900,
      lines: plan_lines,
      has_more: true
    )
    snapshot = RecordingStudioStripe::WebhookEvent.find_by!(stripe_id: "evt_has_more").payload["invoice"]
    assert snapshot["lines_has_more"]
    assert_equal 1, snapshot["lines"].size
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

  def post_invoice(event_id, invoice_id, stripe_subscription_id, amount:, lines:, created: 1_700_000_000,
                   billing_reason: nil, has_more: false, success: :success)
    invoice = {
      "id" => invoice_id,
      "amount_paid" => amount,
      "currency" => "usd",
      "customer" => "cus_#{stripe_subscription_id}",
      "parent" => {
        "type" => "subscription_details",
        "subscription_details" => { "subscription" => stripe_subscription_id }
      },
      "lines" => { "data" => lines, "has_more" => has_more }
    }
    invoice["billing_reason"] = billing_reason if billing_reason
    post "/webhooks/stripe",
         params: stripe_event(event_id, "invoice.paid", invoice, created: created),
         as: :json
    assert_response success
  end

  def signed_header(payload, secret)
    timestamp = Time.now
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, secret)
    Stripe::Webhook::Signature.generate_header(timestamp, signature)
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

class DomainEventConcurrentPublishTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    root = RecordingStudio.root_recording_for(workspace)
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    @subscription = RecordingStudioStripe::ApplySubscription.call(
      root_recording: root,
      price: price,
      stripe_subscription_id: "sub_concurrent_publish",
      stripe_customer_id: "cus_concurrent_publish",
      status: "active"
    )
    @event = RecordingStudioStripe::DomainEvent.create!(
      name: "invoice_paid",
      idempotency_key: "invoice_paid/in_concurrent",
      subscription: @subscription,
      customer_id: @subscription.customer_id,
      root_recording_id: @subscription.root_recording_id,
      occurred_at: Time.current,
      payload: { "amount" => 2900, "currency" => "usd", "invoice_id" => "in_concurrent", "first_payment" => true }
    )
    @event.update_column(:published_at, nil)
  end

  teardown do
    RecordingStudioStripe::DomainEvent.where(subscription_id: @subscription&.id).delete_all
    customer = @subscription&.customer
    @subscription&.delete
    customer&.delete
  end

  test "only one of two concurrent publishes instruments the event" do
    ready = Queue.new
    start = Queue.new
    name = RecordingStudioStripe::DomainEvents::INVOICE_PAID
    delivered = 0
    delivered_mutex = Mutex.new
    listener = ActiveSupport::Notifications.subscribe(name) do
      delivered_mutex.synchronize { delivered += 1 }
    end

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          RecordingStudioStripe::DomainEvent.find(@event.id).publish!
        end
      end
    end

    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:join)

    assert_equal 1, delivered
    assert_predicate @event.reload, :published_at
  ensure
    ActiveSupport::Notifications.unsubscribe(listener) if listener
  end
end

class ErrorRecorder
  attr_reader :errors, :handled

  def initialize
    @errors = []
    @handled = []
  end

  def report(error, handled:, severity:, context:, source:)
    @errors << error
    @handled << handled
  end
end

class RetrievedSubscriptionClient
  def initialize(subscription)
    @subscription = subscription
  end

  def v1
    self
  end

  def subscriptions
    self
  end

  def retrieve(_id)
    @subscription
  end
end
