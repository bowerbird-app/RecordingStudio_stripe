# frozen_string_literal: true

require "test_helper"
require "timeout"

module QuantityLimitLockSpy
  def hold(connection, name)
    if Thread.current[:capture_quantity_limit_locks]
      Thread.current[:quantity_limit_lock_names] << name
    end
    super
  end
end

unless RecordingStudioStripe::AdvisoryLock.singleton_class.ancestors.include?(QuantityLimitLockSpy)
  RecordingStudioStripe::AdvisoryLock.singleton_class.prepend(QuantityLimitLockSpy)
end

class QuantityLimitsTest < ActiveSupport::TestCase
  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @previous_limits = RecordingStudioStripe.configuration.limits
    @previous_usages = RecordingStudioStripe.configuration.limit_usages.dup
    @workspace = Workspace.create!(name: "Quantity Studio #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    @starter = RecordingStudioStripe::Product.find_by!(name: "Starter")
    @usage = 3_500_000_000
    configure_quantity_limit
    @starter.assign_limits("press_kits" => 3, "storage_bytes" => 5_000_000_000)
    @starter.save!
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: @starter.monthly_price)
    register_storage_usage
  end

  teardown do
    RecordingStudioStripe.configuration.limits = @previous_limits
    RecordingStudioStripe.configuration.limit_usages.replace(@previous_usages)
  end

  test "available requires a positive integer and defaults to one" do
    storage = @workspace.billing.limit(:storage_bytes)
    kits = @workspace.billing.limit(:press_kits)

    assert_equal true, storage.available?
    assert_equal true, storage.available?(1)
    assert_equal true, storage.available?(500_000)
    assert_equal true, kits.available?
    assert_equal true, kits.available?(1)
    assert_equal false, kits.available?(500_000)

    [storage, kits].each do |limit|
      [0, -1, 1.5, "100", nil].each do |quantity|
        error = assert_raises(ArgumentError) { limit.available?(quantity) }

        assert_match(/positive integer/, error.message)
      end
    end
  end

  test "quantity limit math uses the provider and the product metadata" do
    storage = @workspace.billing.limit(:storage_bytes)

    assert_equal 5_000_000_000, storage.included
    assert_equal 3_500_000_000, storage.used
    assert_equal 1_500_000_000, storage.remaining
    assert storage.available?(1_500_000_000)
    refute storage.available?(1_500_000_001)
    refute storage.over?
    assert_equal @root.id, @seen_root.id
  end

  test "quantity limit is over when the provider exceeds the product cap" do
    @usage = 5_000_000_001
    storage = @workspace.billing.limit(:storage_bytes)

    assert storage.over?
    refute storage.available?(1)
    assert_equal 0, storage.remaining
  end

  test "product metadata keeps limit_name for count and quantity" do
    assert_equal "3", @starter.metadata["limit_press_kits"]
    assert_equal "5000000000", @starter.metadata["limit_storage_bytes"]
    assert_equal 3, @starter.limit_quantity("press_kits")
    assert_equal 5_000_000_000, @starter.limit_quantity("storage_bytes")
    assert_includes @starter.limit_inclusion_lines, "3 press kits"
    assert_includes @starter.limit_inclusion_lines, "5000000000 storage"

    lines = RecordingStudioStripe::PlanFeatures.for(@starter, @starter.monthly_price)
    storage_line = lines.find { |line| line.key == "limit:storage_bytes" }
    kits_line = lines.find { |line| line.key == "limit:press_kits" }

    assert storage_line
    assert_includes storage_line.text, "storage"
    assert_equal "3 press kits", kits_line.text
  end

  test "monthly and yearly share the quantity and a period change does not reset it" do
    subscription = RecordingStudioStripe::Subscription.current_for(
      root_recording_id: @root.id,
      subscription_type: "studio"
    )
    kits_used = @workspace.billing.limit(:press_kits).used
    storage_used = @workspace.billing.limit(:storage_bytes).used

    subscription.update!(current_period_start: 4.months.ago, current_period_end: 3.months.ago)
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: @starter.annual_price)

    storage = @workspace.billing.limit(:storage_bytes)

    assert_equal 5_000_000_000, storage.included
    assert_equal storage_used, storage.used
    assert_equal kits_used, @workspace.billing.limit(:press_kits).used
    assert_equal 0, RecordingStudioStripe::UsageEntry.where(root_recording_id: @root.id).count
  end

  test "quantity included follows the subscription type" do
    inbox = RecordingStudioStripe::Product.find_by!(name: "Inbox")
    inbox.update!(metadata: inbox.metadata.merge("limit_storage_bytes" => "42"))
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: inbox.monthly_price)

    assert_equal 5_000_000_000, @workspace.billing.limit(:storage_bytes).included
    assert_equal 5_000_000_000, @workspace.billing.line(:studio).limit(:storage_bytes).included
    assert_equal 42, @workspace.billing.line(:inbox).limit(:storage_bytes).included
    assert_equal @usage, @workspace.billing.line(:inbox).limit(:storage_bytes).used
  end

  test "enforce and with_capacity accept a fitting quantity and reject the rest" do
    storage = @workspace.billing.limit(:storage_bytes)
    ran = false

    assert_equal true, storage.enforce!(1_500_000_000)
    assert_equal true, storage.enforce!(1_500_000_000)
    result = storage.with_capacity!(1_500_000_000) do
      ran = true
      :stored
    end
    error = assert_raises(RecordingStudioStripe::PlanLimitReached) do
      storage.with_capacity!(1_500_000_001) { ran = false }
    end

    assert_equal :stored, result
    assert ran
    assert_equal "storage_bytes", error.handle.name
    assert_includes error.user_message, "Starter includes 5000000000 storage."
    assert_includes error.user_message, "Upgrade, or free some up."
    assert_match(/positive integer/, assert_raises(ArgumentError) { storage.enforce!(0) }.message)
  end

  test "a missing plan tells you to pick one" do
    bare = Workspace.create!(name: "No Plan #{SecureRandom.hex(4)}")
    root = RecordingStudio.root_recording_for(bare)
    error = assert_raises(RecordingStudioStripe::PlanLimitReached) do
      bare.billing.limit(:storage_bytes).enforce!(1)
    end

    assert_equal "Pick a plan to add storage.", error.user_message
    assert_equal root.id, error.handle.root_recording.id
  end

  test "quantity usage invalid from the provider is rejected" do
    @usage = -5
    error = assert_raises(ArgumentError) { @workspace.billing.limit(:storage_bytes).used }

    assert_match(/non-negative integer/, error.message)
  end

  test "a missing quantity provider raises" do
    RecordingStudioStripe.configuration.limit_usages.delete("storage_bytes")
    error = assert_raises(ArgumentError) { @workspace.billing.limit(:storage_bytes).used }

    assert_match(/No usage provider registered for limit storage_bytes/, error.message)
  end

  test "quantity limits are not enforced by create restore or move" do
    calls = 0
    RecordingStudioStripe.register_limit_usage(:storage_bytes) do |root_recording|
      calls += 1
      assert_equal @root.id, root_recording.id
      9_999
    end
    @starter.assign_limits("press_kits" => 3, "storage_bytes" => 1)
    @starter.save!

    kit = @root.record(PressKit) { |press_kit| press_kit.name = "Unguarded" }
    @root.record(Folder) { |folder| folder.name = "Still here" }
    kit.update_column(:trashed_at, Time.current)
    kit.update!(trashed_at: nil)

    other = Workspace.create!(name: "Quantity Other #{SecureRandom.hex(4)}")
    other_root = RecordingStudio.root_recording_for(other)
    moving = other_root.record(Folder) { |folder| folder.name = "Traveler" }
    moving.update!(parent_recording_id: @root.id, root_recording_id: @root.id)

    assert_equal 0, calls
    assert_equal @root.id, moving.reload.root_recording_id
  end

  test "a quantity limit keeps recordable_type from becoming a create gate" do
    limits = RecordingStudioStripe.configuration.limits.to_h.deep_stringify_keys
    limits["press_kits"] = limits["press_kits"].merge("aggregation" => "quantity")
    RecordingStudioStripe.configuration.limits = limits
    called = false
    RecordingStudioStripe.register_limit_usage(:press_kits) do
      called = true
      100
    end

    @root.record(PressKit) { |press_kit| press_kit.name = "Not a count" }

    refute called
    assert_predicate RecordingStudioStripe::Limits.fetch(:press_kits), :quantity?
  end

  test "count limits still ignore a usage provider and exclude trashed rows" do
    called = false
    RecordingStudioStripe.register_limit_usage(:press_kits) do
      called = true
      99
    end
    first = @root.record(PressKit) { |kit| kit.name = "Kit 1" }
    @root.record(PressKit) { |kit| kit.name = "Kit 2" }
    first.update_column(:trashed_at, Time.current)
    kits = @workspace.billing.limit(:press_kits)

    assert_equal 1, kits.used
    assert_equal true, kits.enforce!(1)
    assert_equal 1, kits.used
    refute called
    refute_predicate kits, :quantity?

    first.update!(trashed_at: nil)
    @root.record(PressKit) { |kit| kit.name = "Kit 3" }
    error = assert_raises(RecordingStudioStripe::PlanLimitReached) do
      @workspace.billing.limit(:press_kits).enforce!(1)
    end

    assert_equal "press_kits", error.handle.name
    assert_includes error.user_message, "Upgrade, or archive one."
    refute called
  end

  test "count create still locks on the root and recordable type" do
    names = captured_lock_names do
      @root.record(PressKit) { |kit| kit.name = "Locked kit" }
    end

    assert_includes names, "#{@root.id}:PressKit"
  end

  test "quantity enforcement locks on the root and limit name" do
    names = captured_lock_names do
      @workspace.billing.limit(:storage_bytes).with_capacity!(1) { :ok }
    end

    assert_equal ["#{@root.id}:limit:storage_bytes"], names
  end

  test "the fourth press kit is still blocked while a full quantity limit is not consulted" do
    called = false
    RecordingStudioStripe.register_limit_usage(:storage_bytes) do
      called = true
      9_999
    end
    @starter.assign_limits("press_kits" => 3, "storage_bytes" => 1)
    @starter.save!
    3.times { |index| @root.record(PressKit) { |kit| kit.name = "Kit #{index}" } }

    error = assert_raises(RecordingStudioStripe::PlanLimitReached) do
      @root.record(PressKit) { |kit| kit.name = "Kit 4" }
    end

    assert_equal "press_kits", error.handle.name
    refute called
    assert_equal 3, @workspace.billing.limit(:press_kits).used
  end

  private

  def configure_quantity_limit
    limits = @previous_limits.to_h.deep_stringify_keys
    limits["storage_bytes"] = {
      "label" => "Storage",
      "aggregation" => "quantity",
      "subscription_type" => "studio"
    }
    RecordingStudioStripe.configuration.limits = limits
  end

  def register_storage_usage
    test = self
    RecordingStudioStripe.register_limit_usage(:storage_bytes) do |root_recording|
      test.instance_variable_set(:@seen_root, root_recording)
      test.instance_variable_get(:@usage)
    end
  end

  def captured_lock_names
    Thread.current[:quantity_limit_lock_names] = []
    Thread.current[:capture_quantity_limit_locks] = true
    yield
    Thread.current[:quantity_limit_lock_names].dup
  ensure
    Thread.current[:capture_quantity_limit_locks] = false
  end
end

class QuantityLimitConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @previous_limits = RecordingStudioStripe.configuration.limits
    @previous_usages = RecordingStudioStripe.configuration.limit_usages.dup
    limits = @previous_limits.to_h.deep_stringify_keys
    limits["storage_bytes"] = {
      "label" => "Storage",
      "aggregation" => "quantity",
      "subscription_type" => "studio"
    }
    RecordingStudioStripe.configuration.limits = limits
    @workspace = Workspace.create!(name: "Quantity Lock #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    @product = RecordingStudioStripe::Product.create!(
      name: "Quantity Cap #{SecureRandom.hex(4)}",
      kind: "plan",
      stripe_id: "prod_quantity_#{SecureRandom.hex(4)}",
      subscription_type: "studio",
      metadata: {
        "kind" => "plan",
        "subscription_type" => "studio",
        "limit_storage_bytes" => "1000"
      }
    )
    @price = @product.prices.create!(
      stripe_id: "price_quantity_#{SecureRandom.hex(4)}",
      unit_amount: 100,
      interval: "month",
      currency: "usd",
      active: true,
      metadata: {}
    )
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: @price)
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS quantity_limit_probe")
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      CREATE TABLE quantity_limit_probe (
        root_recording_id uuid PRIMARY KEY,
        amount bigint NOT NULL
      )
    SQL
    register_probe_usage
  end

  teardown do
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS quantity_limit_probe")
    cleanup_records
    RecordingStudioStripe.configuration.limits = @previous_limits
    RecordingStudioStripe.configuration.limit_usages.replace(@previous_usages || {})
  end

  test "with_capacity commits a fitting write and rolls back a failed one" do
    handle = @workspace.billing.limit(:storage_bytes)

    handle.with_capacity!(600) { write_probe(600) }

    assert_equal 600, probe_amount
    assert_raises(RecordingStudioStripe::PlanLimitReached) do
      handle.with_capacity!(600) { write_probe(600) }
    end
    assert_equal 600, probe_amount

    assert_raises(RuntimeError) do
      handle.with_capacity!(100) do
        write_probe(100)
        raise "nope"
      end
    end
    assert_equal 600, probe_amount
  end

  test "simultaneous quantity writes keep only what fits under the advisory lock" do
    names = Queue.new
    ready = Queue.new
    go = Queue.new
    threads = Array.new(2) do
      Thread.new do
        Rails.application.executor.wrap do
          ActiveRecord::Base.connection_pool.with_connection do
            Thread.current[:capture_quantity_limit_locks] = true
            Thread.current[:quantity_limit_lock_names] = []
            ready << true
            go.pop
            begin
              @workspace.billing.limit(:storage_bytes).with_capacity!(600) do
                sleep 0.2
                write_probe(600)
              end
              :ok
            rescue RecordingStudioStripe::PlanLimitReached
              :blocked
            ensure
              Thread.current[:quantity_limit_lock_names].each { |name| names << name }
            end
          end
        end
      end
    end

    Timeout.timeout(15) do
      2.times { ready.pop }
      2.times { go << true }
      results = threads.map(&:value)
      assert_equal 1, results.count(:ok)
      assert_equal 1, results.count(:blocked)
    end

    assert_equal 600, probe_amount
    assert_equal 2, names.size
    names.size.times do
      assert_equal "#{@root.id}:limit:storage_bytes", names.pop
    end
  end

  private

  def register_probe_usage
    RecordingStudioStripe.register_limit_usage(:storage_bytes) do |root_recording|
      connection = RecordingStudio::Recording.connection
      quoted_id = connection.quote(root_recording.id)
      value = connection.select_value(
        "SELECT amount FROM quantity_limit_probe WHERE root_recording_id = #{quoted_id}"
      )
      value.nil? ? 0 : Integer(value)
    end
  end

  def write_probe(amount)
    connection = RecordingStudio::Recording.connection
    quoted_id = connection.quote(@root.id)
    quoted_amount = connection.quote(amount)
    connection.execute(<<~SQL.squish)
      INSERT INTO quantity_limit_probe (root_recording_id, amount)
      VALUES (#{quoted_id}, #{quoted_amount})
      ON CONFLICT (root_recording_id)
      DO UPDATE SET amount = quantity_limit_probe.amount + EXCLUDED.amount
    SQL
  end

  def probe_amount
    quoted_id = ActiveRecord::Base.connection.quote(@root.id)
    value = ActiveRecord::Base.connection.select_value(
      "SELECT amount FROM quantity_limit_probe WHERE root_recording_id = #{quoted_id}"
    )
    value.nil? ? 0 : Integer(value)
  end

  def cleanup_records
    return unless @root

    RecordingStudioStripe::Subscription.where(root_recording_id: @root.id).delete_all
    RecordingStudioStripe::Customer.where(root_recording_id: @root.id).delete_all
    recordings = RecordingStudio::Recording.where(root_recording_id: @root.id).or(
      RecordingStudio::Recording.where(id: @root.id)
    )
    recording_ids = recordings.pluck(:id)
    RecordingStudio::Event.where(recording_id: recording_ids).delete_all
    RecordingStudio::Recording.where(id: recording_ids).update_all(parent_recording_id: nil, root_recording_id: nil)
    RecordingStudio::Recording.where(id: recording_ids).delete_all
    @workspace&.delete
    @price&.delete
    @product&.delete
  end
end
