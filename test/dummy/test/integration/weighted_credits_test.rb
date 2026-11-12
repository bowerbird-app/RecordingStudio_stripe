# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

module CreditMeterLockSpy
  def hold(connection, name)
    if Thread.current[:capture_credit_meter_locks]
      Thread.current[:credit_meter_lock_names] << name
    end
    super
  end
end

lock_ancestors = RecordingStudioStripe::AdvisoryLock.singleton_class.ancestors
unless lock_ancestors.any? { |ancestor| %w[QuantityLimitLockSpy CreditMeterLockSpy].include?(ancestor.name) }
  RecordingStudioStripe::AdvisoryLock.singleton_class.prepend(CreditMeterLockSpy)
end

class WeightedCreditsTest < ActiveSupport::TestCase
  setup do
    config = RecordingStudioStripe.configuration
    @previous_meters = config.meters
    @previous_costs = config.usage_costs
    @previous_types = config.subscription_types
    config.meters = @previous_meters.merge(
      "credits" => {
        "label" => "Credits",
        "icon" => "sparkles",
        "plan_line" => "%{quantity} credits each period"
      }
    )
    config.usage_costs = {
      "ai.jev" => 1,
      "web.brave" => 5,
      "web.reader" => 2
    }
    config.subscription_types = @previous_types.merge("pressbot" => { "label" => "Pressbot" })
    RecordingStudioStripe::Meter.sync_from_config!
    @workspace = Workspace.create!(name: "Credits #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    @billing = @workspace.billing
  end

  teardown do
    config = RecordingStudioStripe.configuration
    config.meters = @previous_meters
    config.usage_costs = @previous_costs
    config.subscription_types = @previous_types
  end

  test "a plan spend records credits and the source tariff" do
    price = plan_price(type: "pressbot", included: 100)
    subscribe(price)

    entry = pressbot.spend_usage(key: "web.brave", quantity: 1, idempotency_key: "search:1")

    assert_equal "credits", entry.meter.name
    assert_equal 5, entry.quantity
    assert_equal "web.brave", entry.usage_key
    assert_equal 1, entry.source_quantity
    assert_equal 5, entry.credit_rate
    assert_equal "pressbot", entry.subscription_type
    assert_equal 5, pressbot.meter(:credits).usage
    assert_equal 95, pressbot.meter(:credits).remaining
  end

  test "a raw meter spend leaves the source columns empty" do
    subscribe(plan_price(type: "pressbot", included: 100))

    entry = pressbot.meter(:credits).spend(4)

    assert_equal 4, entry.quantity
    assert_nil entry.usage_key
    assert_nil entry.source_quantity
    assert_nil entry.credit_rate
  end

  test "spending more credits than remain raises and writes nothing" do
    subscribe(plan_price(type: "pressbot", included: 3))

    assert_raises(RecordingStudioStripe::MeterLimitReached) do
      pressbot.spend_usage(key: "web.brave")
    end
    assert_equal 0, usage_count
    assert_equal 3, pressbot.meter(:credits).remaining
  end

  test "the same idempotency key spends credits once" do
    subscribe(plan_price(type: "pressbot", included: 100))

    first = pressbot.spend_usage(key: "web.brave", quantity: 1, idempotency_key: "search:abc123")
    second = pressbot.spend_usage(key: "web.brave", quantity: 1, idempotency_key: "search:abc123")

    assert_equal first.id, second.id
    assert_equal 5, pressbot.meter(:credits).usage
    assert_equal 1, usage_count
  end

  test "a later tariff change does not rewrite the recorded rate" do
    subscribe(plan_price(type: "pressbot", included: 100))
    entry = pressbot.spend_usage(key: "web.brave", quantity: 1)

    RecordingStudioStripe.configuration.usage_costs = { "web.brave" => 3, "ai.jev" => 1 }
    later = pressbot.spend_usage(key: "web.brave", quantity: 1, idempotency_key: "later")

    assert_equal 5, entry.reload.credit_rate
    assert_equal 5, entry.quantity
    assert_equal 3, later.credit_rate
    assert_equal 3, later.quantity
    assert_equal 8, pressbot.meter(:credits).usage
  end

  test "several usage keys add up on the credits meter" do
    subscribe(plan_price(type: "pressbot", included: 100))

    pressbot.spend_usage(key: "ai.jev", quantity: 4)
    pressbot.spend_usage(key: "web.brave", quantity: 2)

    assert_equal 14, pressbot.meter(:credits).usage
    assert_equal 86, pressbot.meter(:credits).remaining
  end

  test "cost and availability checks do not record usage" do
    subscribe(plan_price(type: "pressbot", included: 100))

    assert_equal 10, pressbot.usage_cost(key: "web.brave", quantity: 2)
    assert_equal 10, @billing.usage_cost(key: "web.brave", quantity: 2)
    assert pressbot.usage_available?(key: "web.brave", quantity: 2)
    refute pressbot.usage_available?(key: "web.brave", quantity: 30)
    assert_equal 0, usage_count
  end

  test "included credits come from the current price" do
    product_name = "Pressbot Pro #{SecureRandom.hex(3)}"
    weekly = plan_price(type: "pressbot", included: 1_000, interval: "week", name: product_name)
    monthly = RecordingStudioStripe::CreatePrice.call(
      product: weekly.product,
      unit_amount: 2_900,
      interval: "month",
      metadata: { "included_credits" => "5000" }
    )
    subscribe(weekly, start_at: 1.day.ago, end_at: 6.days.from_now)
    pressbot.spend_usage(key: "web.brave", quantity: 1)

    assert_equal 1_000, pressbot.meter(:credits).included
    assert_equal 995, pressbot.meter(:credits).remaining
    assert_includes plan_lines(weekly), "1k credits each period"

    subscribe(monthly, start_at: 1.day.ago, end_at: 20.days.from_now)

    assert_equal monthly.id, pressbot.subscription.price_id
    assert_equal 5_000, pressbot.meter(:credits).included
    assert_equal 5, pressbot.meter(:credits).usage
    assert_equal 4_995, pressbot.meter(:credits).remaining
    assert_includes plan_lines(monthly), "5k credits each period"
    refute_includes plan_lines(weekly), "5k credits each period"
  end

  test "purchased credits increase remaining through the usage period" do
    subscribe(plan_price(type: "pressbot", included: 5_000))
    buy_pack(type: "pressbot", allowance: 2_000)
    pressbot.spend_usage(key: "web.brave", quantity: 680)

    meter = pressbot.meter(:credits)
    assert_equal 5_000, meter.included
    assert_equal 2_000, meter.purchased
    assert_equal 3_400, meter.usage
    assert_equal 3_600, meter.remaining
  end

  test "a pressbot spend does not consume studio credits" do
    subscribe(plan_price(type: "pressbot", included: 100))
    subscribe(plan_price(type: "studio", included: 80))

    pressbot.spend_usage(key: "web.brave", quantity: 1)

    assert_equal 5, pressbot.meter(:credits).usage
    assert_equal 95, pressbot.meter(:credits).remaining
    assert_equal 0, studio.meter(:credits).usage
    assert_equal 80, studio.meter(:credits).remaining
  end

  test "a pressbot credit pack is not available to studio" do
    subscribe(plan_price(type: "pressbot", included: 100))
    subscribe(plan_price(type: "studio", included: 80))
    buy_pack(type: "pressbot", allowance: 2_000)

    assert_equal 2_000, pressbot.meter(:credits).purchased
    assert_equal 2_100, pressbot.meter(:credits).remaining
    assert_equal 0, studio.meter(:credits).purchased
    assert_equal 80, studio.meter(:credits).remaining
    assert pressbot.usage_available?(key: "web.brave", quantity: 400)
    refute studio.usage_available?(key: "web.brave", quantity: 20)
  end

  test "weighted usage stays inside the selected line period" do
    subscribe(
      plan_price(type: "studio", included: 100),
      start_at: 10.days.ago,
      end_at: 20.days.from_now
    )
    subscribe(
      plan_price(type: "pressbot", included: 100),
      start_at: 2.days.ago,
      end_at: 28.days.from_now
    )

    studio.spend_usage(key: "web.reader", quantity: 2, recorded_at: 5.days.ago)
    pressbot.spend_usage(key: "web.brave", quantity: 1)

    assert_equal 4, studio.meter(:credits).usage
    assert_equal 5, pressbot.meter(:credits).usage
    assert_equal 96, studio.meter(:credits).remaining
    assert_equal 95, pressbot.meter(:credits).remaining
  end

  test "unscoped spend does not pool packs when no plan is live" do
    buy_pack(type: "pressbot", allowance: 2_000)
    buy_pack(type: "studio", allowance: 1_000)

    error = assert_raises(RecordingStudioStripe::SubscriptionLineRequired) do
      @billing.spend_usage(key: "web.brave")
    end

    assert_equal "credits", error.meter
    assert_equal "Cannot determine which subscription line should spend credits. Use billing.line(:type).",
                 error.message
    assert_raises(RecordingStudioStripe::SubscriptionLineRequired) do
      @billing.usage_available?(key: "web.brave")
    end
    assert_equal 0, usage_count
    assert_equal 2_000, pressbot.meter(:credits).purchased
    assert_equal 1_000, studio.meter(:credits).purchased

    entry = pressbot.spend_usage(key: "web.brave")

    assert_equal 5, entry.quantity
    assert_equal "pressbot", entry.subscription_type
    assert_equal 1_995, pressbot.meter(:credits).remaining
    assert_equal 1_000, studio.meter(:credits).remaining
  end

  test "a line with only purchased credits can spend usage" do
    subscribe(plan_price(type: "pressbot", included: 0))
    buy_pack(type: "pressbot", allowance: 2_000)

    entry = pressbot.spend_usage(key: "web.brave")

    assert_equal 5, entry.quantity
    assert_equal "web.brave", entry.usage_key
    assert_equal 1, entry.source_quantity
    assert_equal 5, entry.credit_rate
    assert_equal "pressbot", entry.subscription_type
    assert_equal 1_995, pressbot.meter(:credits).remaining
  end

  test "weighted source fields are rejected on a non-credit meter" do
    subscribe(plan_price(type: "pressbot", included: 100, extra_metadata: { "included_api_calls" => "100" }))

    error = assert_raises(ArgumentError) do
      pressbot.meter(:api_calls).spend(
        5,
        usage_key: "web.brave",
        source_quantity: 1,
        credit_rate: 5
      )
    end

    assert_equal "usage source belongs on the credits meter", error.message
    assert_equal 0, pressbot.meter(:api_calls).usage

    entry = pressbot.meter(:api_calls).spend(5)

    assert_equal 5, entry.quantity
    assert_nil entry.usage_key
    assert_nil entry.source_quantity
    assert_nil entry.credit_rate
    assert_equal 5, pressbot.meter(:api_calls).usage
  end

  test "one subscription type can still spend credits without a live plan" do
    RecordingStudioStripe.configuration.subscription_types = { "studio" => { "label" => "Studio" } }
    buy_pack(type: "studio", allowance: 100)

    entry = @billing.spend_usage(key: "web.brave")

    assert_equal 5, entry.quantity
    assert_equal 95, @billing.meter(:credits).remaining
  end

  test "unscoped spend uses the only plan that holds credits" do
    subscribe(plan_price(type: "pressbot", included: 100))

    entry = @billing.spend_usage(key: "web.brave", quantity: 1)

    assert_equal "pressbot", entry.subscription_type
    assert_equal 5, pressbot.meter(:credits).usage
    assert @billing.usage_available?(key: "ai.jev", quantity: 10)
  end

  test "unscoped spend fails when two plans hold credits" do
    subscribe(plan_price(type: "studio", included: 1_000))
    subscribe(plan_price(type: "pressbot", included: 0))
    buy_pack(type: "pressbot", allowance: 2_000)

    assert_equal 1_000, @billing.meter(:credits).included
    assert_equal 10, @billing.usage_cost(key: "web.brave", quantity: 2)
    error = assert_raises(RecordingStudioStripe::AmbiguousSubscriptionLine) do
      @billing.spend_usage(key: "web.brave")
    end
    assert_equal "credits", error.meter
    assert_raises(RecordingStudioStripe::AmbiguousSubscriptionLine) do
      @billing.usage_available?(key: "web.brave")
    end
    assert_equal 0, usage_count

    entry = pressbot.spend_usage(key: "web.brave", quantity: 1)

    assert_equal "pressbot", entry.subscription_type
    assert_equal 5, pressbot.meter(:credits).usage
    assert_equal 0, studio.meter(:credits).usage
    assert_equal 1_000, studio.meter(:credits).remaining
    assert_equal 1_995, pressbot.meter(:credits).remaining
  end

  test "record_credits stores the amount and leaves the tariff empty" do
    subscribe(plan_price(type: "pressbot", included: 100))

    RecordingStudioStripe::Client.stub(:current, -> { raise "stripe called" }) do
      entry = pressbot.record_credits(
        amount: 7,
        breakdown: { model: "jev", tokens: { "input" => 12 } },
        idempotency_key: "ai-attempt:7"
      )

      assert_equal 7, entry.quantity
      assert_equal "ai", entry.usage_key
      assert_nil entry.source_quantity
      assert_nil entry.credit_rate
      assert_equal({ "model" => "jev", "tokens" => { "input" => 12 } }, entry.reload.breakdown)
      assert_equal "pressbot", entry.subscription_type
      assert entry.valid?
      assert_equal 93, pressbot.meter(:credits).remaining
    end
  end

  test "billing record_credits uses the line that holds credits" do
    subscribe(plan_price(type: "pressbot", included: 40))

    entry = @billing.record_credits(
      amount: 4,
      breakdown: { "kind" => "decision" },
      idempotency_key: "ai-hosted-agent-turn:4"
    )

    assert_equal "pressbot", entry.subscription_type
    assert @billing.credits_available?(minimum: 36)
    refute @billing.credits_available?(minimum: 37)
  end

  test "record_credits rejects amounts and breakdowns it cannot store" do
    subscribe(plan_price(type: "pressbot", included: 20))
    breakdown = { "kind" => "attempt" }

    assert_raises(ArgumentError) { pressbot.record_credits(amount: 1.5, breakdown:, idempotency_key: "float") }
    assert_raises(ArgumentError) { pressbot.record_credits(amount: 0, breakdown:, idempotency_key: "zero") }
    assert_raises(ArgumentError) { pressbot.record_credits(amount: -3, breakdown:, idempotency_key: "neg") }
    assert_raises(ArgumentError) { pressbot.record_credits(amount: 1, breakdown:, idempotency_key: "  ") }
    assert_raises(ArgumentError) { pressbot.record_credits(amount: 1, breakdown:, idempotency_key: nil) }
    assert_raises(ArgumentError) { pressbot.record_credits(amount: 1, breakdown: "nope", idempotency_key: "text") }
    assert_raises(ArgumentError) do
      pressbot.record_credits(amount: 1, breakdown: { "note" => "x" * 20_000 }, idempotency_key: "huge")
    end
    assert_raises(ArgumentError) do
      pressbot.meter(:api_calls).record_credits(amount: 1, breakdown:, idempotency_key: "other-meter")
    end
    assert_equal 0, usage_count
    assert_equal 20, pressbot.meter(:credits).remaining
  end

  test "the same idempotency key records credits once" do
    subscribe(plan_price(type: "pressbot", included: 50))
    breakdown = { "kind" => "attempt" }

    first = pressbot.record_credits(amount: 6, breakdown:, idempotency_key: "ai-attempt:same")
    second = pressbot.record_credits(amount: 6, breakdown: { "kind" => "other" }, idempotency_key: "ai-attempt:same")

    assert_equal first.id, second.id
    assert_equal({ "kind" => "attempt" }, second.reload.breakdown)
    assert_equal 1, usage_count
    assert_equal 6, pressbot.meter(:credits).usage
  end

  test "a repeated key with a different amount keeps the first row" do
    subscribe(plan_price(type: "pressbot", included: 50))
    first = pressbot.record_credits(amount: 6, breakdown: { "kind" => "attempt" }, idempotency_key: "ai-attempt:diff")
    warnings = []

    second = Rails.logger.stub(:warn, ->(message = nil, **) { warnings << message.to_s }) do
      pressbot.record_credits(amount: 9, breakdown: { "kind" => "attempt" }, idempotency_key: "ai-attempt:diff")
    end

    assert_equal first.id, second.id
    assert_equal 6, second.reload.quantity
    assert_equal 1, usage_count
    assert_equal 44, pressbot.meter(:credits).remaining
    assert_includes warnings.join, "ignored 9"
    assert_includes warnings.join, "recorded 6"
  end

  test "record_credits still writes after the balance is gone" do
    subscribe(plan_price(type: "pressbot", included: 10))

    pressbot.record_credits(amount: 15, breakdown: { "kind" => "attempt" }, idempotency_key: "ai-attempt:over")
    pressbot.record_credits(amount: 1, breakdown: { "kind" => "attempt" }, idempotency_key: "ai-attempt:more")

    assert_equal 16, pressbot.meter(:credits).usage
    assert_equal 0, pressbot.meter(:credits).remaining
    refute pressbot.credits_available?(minimum: 1)
  end

  test "credits_available? compares the whole credit minimum to remaining" do
    subscribe(plan_price(type: "pressbot", included: 10))

    assert pressbot.credits_available?(minimum: 10)
    refute pressbot.credits_available?(minimum: 11)
    assert_raises(ArgumentError) { pressbot.credits_available?(minimum: 1.0) }
    assert_raises(ArgumentError) { pressbot.credits_available?(minimum: 0) }
  end

  test "record_credits uses the same meter lock as spend" do
    subscribe(plan_price(type: "pressbot", included: 100))
    names = captured_meter_locks do
      pressbot.spend_usage(key: "web.brave", quantity: 1, idempotency_key: "lock-spend")
      pressbot.record_credits(amount: 4, breakdown: { "kind" => "attempt" }, idempotency_key: "lock-record")
    end

    assert_equal ["#{@root.id}:meter:credits"], names.uniq
    assert_equal 2, names.size
  end

  test "a spend row still needs the tariff and a priced row does not" do
    subscribe(plan_price(type: "pressbot", included: 100))
    spent = pressbot.spend_usage(key: "web.brave", quantity: 1, idempotency_key: "search:tariff")

    assert spent.valid?
    assert_nil spent.breakdown
    assert_equal 5, spent.source_quantity * spent.credit_rate

    priced = pressbot.record_credits(amount: 3, breakdown: {}, idempotency_key: "ai-attempt:empty")
    assert_nil priced.source_quantity
    assert_nil priced.credit_rate
    assert_equal({}, priced.breakdown)

    bare = RecordingStudioStripe::UsageEntry.new(
      root_recording_id: @root.id,
      meter: RecordingStudioStripe::Meter.fetch("credits"),
      quantity: 1,
      recorded_at: Time.current,
      usage_key: "ai"
    )
    refute_predicate bare, :valid?

    other_meter = RecordingStudioStripe::UsageEntry.new(
      root_recording_id: @root.id,
      meter: RecordingStudioStripe::Meter.fetch("api_calls"),
      quantity: 1,
      recorded_at: Time.current,
      usage_key: "ai",
      breakdown: { "kind" => "attempt" }
    )
    refute_predicate other_meter, :valid?
  end

  test "usage entries store breakdown as nullable jsonb" do
    column = RecordingStudioStripe::UsageEntry.columns_hash.fetch("breakdown")

    assert column.null
    assert_equal :jsonb, column.type
  end

  test "an allowance card titles a credit pack from the meter label" do
    price = pack_price(type: "pressbot", allowance: 5_000, unit_amount: 3_900)
    component = RecordingStudioStripe::AllowanceCardComponent.new(price: price)

    assert_equal "+5k credits", component.send(:pack_title)
    assert_equal "$39", price.formatted_amount
  end

  private

  def captured_meter_locks
    ancestors = RecordingStudioStripe::AdvisoryLock.singleton_class.ancestors
    if ancestors.any? { |ancestor| ancestor.name == "QuantityLimitLockSpy" }
      Thread.current[:quantity_limit_lock_names] = []
      Thread.current[:capture_quantity_limit_locks] = true
      yield
      Thread.current[:quantity_limit_lock_names].dup
    else
      Thread.current[:credit_meter_lock_names] = []
      Thread.current[:capture_credit_meter_locks] = true
      yield
      Thread.current[:credit_meter_lock_names].dup
    end
  ensure
    Thread.current[:capture_quantity_limit_locks] = false
    Thread.current[:capture_credit_meter_locks] = false
  end

  def pressbot
    @billing.line(:pressbot)
  end

  def studio
    @billing.line(:studio)
  end

  def usage_count
    RecordingStudioStripe::UsageEntry.where(root_recording_id: @root.id).count
  end

  def plan_lines(price)
    RecordingStudioStripe::PlanFeatures.for(price.product, price).map(&:text)
  end

  def plan_price(type:, included:, interval: "month", name: nil, extra_metadata: {})
    product = RecordingStudioStripe::CreateProduct.call(
      name: name || "#{type} #{interval} #{included} #{SecureRandom.hex(3)}",
      kind: "plan",
      subscription_type: type
    )
    RecordingStudioStripe::CreatePrice.call(
      product: product,
      unit_amount: 1_000,
      interval: interval,
      metadata: { "included_credits" => included.to_s }.merge(extra_metadata)
    )
  end

  def pack_price(type:, allowance:, unit_amount: 3_900)
    product = RecordingStudioStripe::CreateProduct.call(
      name: "#{type} credits #{allowance} #{SecureRandom.hex(3)}",
      kind: "allowance",
      subscription_type: type
    )
    RecordingStudioStripe::CreatePrice.call(
      product: product,
      unit_amount: unit_amount,
      metadata: { "meter" => "credits", "allowance" => allowance.to_s }
    )
  end

  def buy_pack(type:, allowance:)
    RecordingStudioStripe::ApplyAllowance.call(
      root_recording: @root,
      price: pack_price(type: type, allowance: allowance),
      email: "credits@example.com"
    )
  end

  def subscribe(price, start_at: 3.days.ago, end_at: 27.days.from_now)
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: price,
      email: "credits@example.com",
      current_period_start: start_at,
      current_period_end: end_at
    )
  end
end
