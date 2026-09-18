# frozen_string_literal: true

require "test_helper"

class TrialTest < Minitest::Test
  ProductStub = Struct.new(:metadata, keyword_init: true)

  def test_offered_when_days_are_a_positive_integer
    trial = RecordingStudioStripe::Trial.for(
      ProductStub.new(metadata: { "trial_days" => "14", "trial_unit_amount" => "100" })
    )

    assert trial.offered?
    assert_equal 14, trial.days
    assert_equal 100, trial.unit_amount
    assert_equal "Try for $1", trial.checkout_label
  end

  def test_checkout_label_keeps_cents_when_the_amount_is_not_whole_dollars
    trial = RecordingStudioStripe::Trial.for(
      ProductStub.new(metadata: { "trial_days" => "7", "trial_unit_amount" => "150" })
    )

    assert_equal "Try for $1.50", trial.checkout_label
  end

  def test_zero_amount_uses_start_trial
    trial = RecordingStudioStripe::Trial.for(
      ProductStub.new(metadata: { "trial_days" => "14", "trial_unit_amount" => "0" })
    )

    assert trial.offered?
    assert_equal 0, trial.unit_amount
    assert_equal "Start trial", trial.checkout_label
  end

  def test_not_offered_when_days_are_blank_or_zero
    blank = RecordingStudioStripe::Trial.for(
      ProductStub.new(metadata: { "trial_days" => "", "trial_unit_amount" => "100" })
    )
    missing = RecordingStudioStripe::Trial.for(ProductStub.new(metadata: { "trial_unit_amount" => "100" }))
    zero = RecordingStudioStripe::Trial.for(ProductStub.new(metadata: { "trial_days" => "0" }))

    refute blank.offered?
    refute missing.offered?
    refute zero.offered?
    assert_equal 0, blank.days
  end

  def test_apply_to_checkout_sets_trial_fields_and_keeps_the_plan_price_first
    plan = Struct.new(:stripe_id).new("price_plan")
    fee = Struct.new(:stripe_id, :metadata, :active, :currency, keyword_init: true).new(
      stripe_id: "price_fee",
      metadata: { "kind" => "trial_fee" },
      active: true,
      currency: "usd"
    )
    def fee.active?
      active
    end
    product = Struct.new(:metadata, :prices).new(
      { "trial_days" => "14", "trial_unit_amount" => "100" },
      [fee]
    )
    params = {
      line_items: [{ price: "price_plan", quantity: 1 }],
      subscription_data: { metadata: { root_recording_id: "abc" } }
    }

    RecordingStudioStripe::Trial.for(product).apply_to_checkout(params, plan_price: plan)

    assert_equal [
      { price: "price_plan", quantity: 1 },
      { price: "price_fee", quantity: 1 }
    ], params[:line_items]
    assert_equal 14, params[:subscription_data][:trial_period_days]
    assert_equal "always", params[:payment_method_collection]
    assert_equal({ root_recording_id: "abc" }, params[:subscription_data][:metadata])
  end

  def test_apply_to_checkout_skips_trial_fields_when_not_offered
    plan = Struct.new(:stripe_id).new("price_plan")
    product = Struct.new(:metadata, :prices).new({}, [])
    params = {
      line_items: [{ price: "price_plan", quantity: 1 }],
      subscription_data: { metadata: { root_recording_id: "abc" } }
    }

    RecordingStudioStripe::Trial.for(product).apply_to_checkout(params, plan_price: plan)

    assert_equal [{ price: "price_plan", quantity: 1 }], params[:line_items]
    refute params[:subscription_data].key?(:trial_period_days)
    refute params.key?(:payment_method_collection)
  end

  def test_apply_to_checkout_keeps_a_zero_amount_trial_on_the_plan_price
    plan = Struct.new(:stripe_id).new("price_plan")
    fee = Struct.new(:stripe_id, :metadata, :active, keyword_init: true).new(
      stripe_id: "price_fee",
      metadata: { "kind" => "trial_fee" },
      active: true
    )
    def fee.active?
      active
    end
    product = Struct.new(:metadata, :prices).new(
      { "trial_days" => "14", "trial_unit_amount" => "0" },
      [fee]
    )
    params = {
      line_items: [{ price: "price_plan", quantity: 1 }],
      subscription_data: { metadata: { root_recording_id: "abc" } }
    }

    RecordingStudioStripe::Trial.for(product).apply_to_checkout(params, plan_price: plan)

    assert_equal [{ price: "price_plan", quantity: 1 }], params[:line_items]
    assert_equal 14, params[:subscription_data][:trial_period_days]
    assert_equal "always", params[:payment_method_collection]
  end
end
