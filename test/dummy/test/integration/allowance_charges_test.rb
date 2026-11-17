# frozen_string_literal: true

require "test_helper"

class AllowanceChargesTest < ActionDispatch::IntegrationTest
  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    @root = RecordingStudio.create_root_recording!(@workspace, actor: root_actor)
  end

  test "full refund revokes an unused allowance pack" do
    price = allowance_price
    post_stripe(
      "evt_cs_full",
      "checkout.session.completed",
      checkout_session(price, "cs_full", "pi_full")
    )

    purchase = RecordingStudioStripe::AllowancePurchase.find_by!(stripe_checkout_session_id: "cs_full")
    assert_equal "pi_full", purchase.stripe_payment_intent_id
    assert_equal 5_000_000, tokens.purchased

    post_stripe("evt_refund_full", "charge.refunded", charge("pi_full", amount: 1_000, refunded: 1_000))

    purchase.reload
    assert_equal 5_000_000, purchase.credits_revoked
    assert_equal 0, purchase.credit_shortfall
    assert_equal 1_000, purchase.refunded_amount
    assert_equal 0, tokens.purchased
    assert_equal 0, tokens.remaining

    post_stripe("evt_refund_full_again", "charge.refunded", charge("pi_full", amount: 1_000, refunded: 1_000))

    assert_equal 5_000_000, purchase.reload.credits_revoked
    assert_equal 0, tokens.remaining
  end

  test "partial refund revokes a rounded-down share" do
    purchase = pack!(quantity: 100, payment_intent: "pi_partial", session_id: "cs_partial")

    post_stripe("evt_partial", "charge.refunded", charge("pi_partial", amount: 3, refunded: 2))

    purchase.reload
    assert_equal 66, purchase.credits_revoked
    assert_equal 0, purchase.credit_shortfall
    assert_equal 2, purchase.refunded_amount
    assert_equal 34, tokens.remaining
  end

  test "repeat partial refund uses the cumulative amount" do
    purchase = pack!(quantity: 100, payment_intent: "pi_repeat", session_id: "cs_repeat")

    post_stripe("evt_repeat_1", "charge.refunded", charge("pi_repeat", amount: 3, refunded: 1))
    assert_equal 33, purchase.reload.credits_revoked
    assert_equal 67, tokens.remaining

    post_stripe("evt_repeat_1_again", "charge.refunded", charge("pi_repeat", amount: 3, refunded: 1))
    assert_equal 33, purchase.reload.credits_revoked
    assert_equal 67, tokens.remaining

    post_stripe("evt_repeat_2", "charge.refunded", charge("pi_repeat", amount: 3, refunded: 2))
    assert_equal 66, purchase.reload.credits_revoked
    assert_equal 0, purchase.credit_shortfall
    assert_equal 34, tokens.remaining
  end

  test "a won dispute unfreezes the pack" do
    purchase = pack!(quantity: 100, payment_intent: "pi_won", session_id: "cs_won")

    post_stripe("evt_won_open", "charge.dispute.created", dispute("pi_won", status: "needs_response"))

    assert_predicate purchase.reload, :credits_frozen?
    assert_equal 0, tokens.purchased
    assert_raises(RecordingStudioStripe::MeterLimitReached) { tokens.spend(1) }

    post_stripe("evt_won_open_again", "charge.dispute.created", dispute("pi_won", status: "under_review"))
    assert_predicate purchase.reload, :credits_frozen?

    post_stripe("evt_won_close", "charge.dispute.closed", dispute("pi_won", status: "won"))

    refute_predicate purchase.reload, :credits_frozen?
    assert_equal 0, purchase.credits_revoked
    assert_equal 100, tokens.purchased
    tokens.spend(1)
    assert_equal 99, tokens.remaining

    post_stripe("evt_won_close_again", "charge.dispute.closed", dispute("pi_won", status: "won"))
    refute_predicate purchase.reload, :credits_frozen?
    assert_equal 99, tokens.remaining
  end

  test "a closed inquiry unfreezes the pack" do
    purchase = pack!(quantity: 40, payment_intent: "pi_warning", session_id: "cs_warning")
    post_stripe("evt_warning_open", "charge.dispute.created", dispute("pi_warning", status: "warning_needs_response"))
    post_stripe("evt_warning_close", "charge.dispute.closed", dispute("pi_warning", status: "warning_closed"))

    refute_predicate purchase.reload, :credits_frozen?
    assert_equal 40, tokens.purchased
  end

  test "a lost dispute revokes unused credits" do
    purchase = pack!(quantity: 100, payment_intent: "pi_lost", session_id: "cs_lost")

    post_stripe("evt_lost_open", "charge.dispute.created", dispute("pi_lost", status: "needs_response"))
    post_stripe("evt_lost_close", "charge.dispute.closed", dispute("pi_lost", status: "lost"))

    purchase.reload
    refute_predicate purchase, :credits_frozen?
    assert_equal 100, purchase.credits_revoked
    assert_equal 0, purchase.credit_shortfall
    assert_equal 0, tokens.remaining
    assert_raises(RecordingStudioStripe::MeterLimitReached) { tokens.spend(1) }

    post_stripe("evt_lost_close_again", "charge.dispute.closed", dispute("pi_lost", status: "lost"))
    assert_equal 100, purchase.reload.credits_revoked
    assert_equal 0, tokens.remaining
  end

  test "a lost dispute records a shortfall when credits were spent" do
    purchase = pack!(quantity: 100, payment_intent: "pi_lost_used", session_id: "cs_lost_used")
    tokens.spend(25)

    post_stripe("evt_lost_used_open", "charge.dispute.created", dispute("pi_lost_used", status: "needs_response"))
    assert_equal 0, tokens.purchased
    assert_equal 0, tokens.remaining

    post_stripe("evt_lost_used_close", "charge.dispute.closed", dispute("pi_lost_used", status: "lost"))

    purchase.reload
    refute_predicate purchase, :credits_frozen?
    assert_equal 75, purchase.credits_revoked
    assert_equal 25, purchase.credit_shortfall
    assert_equal 25, tokens.purchased
    assert_equal 25, tokens.usage
    assert_equal 0, tokens.remaining
    assert_operator tokens.included + tokens.purchased - tokens.usage, :>=, 0
  end

  test "used credits are not pulled below zero" do
    purchase = pack!(quantity: 100, payment_intent: "pi_short", session_id: "cs_short")
    tokens.spend(40)

    post_stripe("evt_short", "charge.refunded", charge("pi_short", amount: 1_000, refunded: 1_000))

    purchase.reload
    assert_equal 60, purchase.credits_revoked
    assert_equal 40, purchase.credit_shortfall
    assert_equal 40, tokens.usage
    assert_equal 40, tokens.purchased
    assert_equal 0, tokens.remaining
    assert_operator tokens.included + tokens.purchased - tokens.usage, :>=, 0

    post_stripe("evt_short_again", "charge.refunded", charge("pi_short", amount: 1_000, refunded: 1_000))
    assert_equal 40, purchase.reload.credit_shortfall
    assert_equal 60, purchase.credits_revoked
    assert_equal 0, tokens.remaining
  end

  test "async payment failure records the session and grants nothing" do
    price = allowance_price
    post_stripe(
      "evt_async_fail",
      "checkout.session.async_payment_failed",
      checkout_session(price, "cs_async_fail", "pi_async_fail", payment_status: "unpaid")
    )

    purchase = RecordingStudioStripe::AllowancePurchase.find_by!(stripe_checkout_session_id: "cs_async_fail")
    assert_equal "failed", purchase.status
    assert_equal "pi_async_fail", purchase.stripe_payment_intent_id
    assert_equal 5_000_000, purchase.quantity
    assert_equal 0, tokens.purchased
    assert_equal 0, tokens.remaining

    post_stripe(
      "evt_async_fail_again",
      "checkout.session.async_payment_failed",
      checkout_session(price, "cs_async_fail", "pi_async_fail", payment_status: "unpaid")
    )
    assert_equal 1, RecordingStudioStripe::AllowancePurchase.where(stripe_checkout_session_id: "cs_async_fail").count
    assert_equal 0, tokens.purchased

    post_stripe(
      "evt_async_paid_late",
      "checkout.session.completed",
      checkout_session(price, "cs_async_fail", "pi_async_fail")
    )
    assert_equal "failed", purchase.reload.status
    assert_equal 0, tokens.purchased
  end

  test "async payment failure on a subscription grants nothing" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    post_stripe(
      "evt_async_sub",
      "checkout.session.async_payment_failed",
      {
        "id" => "cs_async_sub",
        "mode" => "subscription",
        "payment_status" => "unpaid",
        "payment_intent" => "pi_async_sub",
        "subscription" => "sub_async_failed",
        "client_reference_id" => @root.id.to_s,
        "metadata" => {
          "root_recording_id" => @root.id.to_s,
          "price_id" => price.stripe_id
        }
      }
    )

    assert_nil @workspace.billing.subscription
    assert_equal 0, RecordingStudioStripe::AllowancePurchase.count
    assert RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_async_sub")
  end

  test "an unrelated charge is stored and ignored" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: price)
    purchase = pack!(quantity: 80, payment_intent: "pi_kept", session_id: "cs_kept")
    included = tokens.included

    post_stripe("evt_other_charge", "charge.refunded", charge("pi_unknown", amount: 500, refunded: 500))

    assert_response :success
    assert RecordingStudioStripe::WebhookEvent.exists?(stripe_id: "evt_other_charge", event_type: "charge.refunded")
    assert_equal 0, purchase.reload.credits_revoked
    assert_equal 0, purchase.credit_shortfall
    assert_equal 80, tokens.purchased
    assert_equal included, tokens.included
    assert_predicate @workspace.billing.subscription, :active?

    post_stripe("evt_other_dispute", "charge.dispute.created", dispute("pi_unknown", status: "needs_response"))
    refute_predicate purchase.reload, :credits_frozen?
    assert_predicate @workspace.billing.subscription, :active?
  end

  private

  def tokens
    @workspace.billing.meter(:ai_tokens)
  end

  def allowance_price
    RecordingStudioStripe::Price.one_time.find_by!("metadata ->> 'allowance' = '5000000'")
  end

  def pack!(quantity:, payment_intent:, session_id:)
    price = allowance_price
    RecordingStudioStripe::AllowancePurchase.create!(
      root_recording_id: @root.id,
      meter: RecordingStudioStripe::Meter.fetch("ai_tokens"),
      price: price,
      quantity: quantity,
      stripe_checkout_session_id: session_id,
      stripe_payment_intent_id: payment_intent,
      purchased_at: Time.current,
      subscription_type: price.product.subscription_type,
      status: RecordingStudioStripe::AllowancePurchase::STATUS_ACTIVE
    )
  end

  def post_stripe(id, type, object)
    post "/webhooks/stripe", params: stripe_event(id, type, object), as: :json
    assert_response :success
  end

  def checkout_session(price, session_id, payment_intent, payment_status: "paid")
    {
      "id" => session_id,
      "mode" => "payment",
      "payment_status" => payment_status,
      "payment_intent" => payment_intent,
      "client_reference_id" => @root.id.to_s,
      "metadata" => {
        "root_recording_id" => @root.id.to_s,
        "price_id" => price.stripe_id
      }
    }
  end

  def charge(payment_intent, amount:, refunded:)
    {
      "id" => "ch_#{payment_intent}",
      "object" => "charge",
      "amount" => amount,
      "amount_refunded" => refunded,
      "refunded" => refunded >= amount,
      "payment_intent" => payment_intent
    }
  end

  def dispute(payment_intent, status:)
    {
      "id" => "dp_#{payment_intent}",
      "object" => "dispute",
      "amount" => 1_000,
      "charge" => "ch_#{payment_intent}",
      "payment_intent" => payment_intent,
      "status" => status
    }
  end

  def stripe_event(id, type, object, created: 1_700_000_000)
    {
      "id" => id,
      "object" => "event",
      "type" => type,
      "created" => created,
      "data" => { "object" => object }
    }
  end
end
