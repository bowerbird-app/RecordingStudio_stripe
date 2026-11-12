# frozen_string_literal: true

require "test_helper"
require "timeout"

class RecordCreditsConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    RecordingStudioStripe::Meter.sync_from_config!
    @workspace = Workspace.create!(name: "Credit lock #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    @product = RecordingStudioStripe::Product.create!(
      stripe_id: "prod_#{SecureRandom.hex(6)}",
      name: "Lock plan #{SecureRandom.hex(3)}",
      kind: "plan",
      subscription_type: "studio"
    )
    @price = RecordingStudioStripe::Price.create!(
      stripe_id: "price_#{SecureRandom.hex(6)}",
      product: @product,
      unit_amount: 1_000,
      currency: "usd",
      interval: "month",
      metadata: { "included_credits" => "100" }
    )
    RecordingStudioStripe::ApplySubscription.call(
      root_recording: @root,
      price: @price,
      email: "locks@example.com",
      current_period_start: 1.day.ago,
      current_period_end: 20.days.from_now
    )
  end

  teardown do
    return unless @root

    RecordingStudioStripe::UsageEntry.where(root_recording_id: @root.id).delete_all
    subscriptions = RecordingStudioStripe::Subscription.where(root_recording_id: @root.id)
    RecordingStudioStripe::DomainEvent.where(subscription_id: subscriptions.select(:id)).delete_all
    subscriptions.delete_all
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

  test "two records of one key leave a single row" do
    key = "ai-attempt:#{SecureRandom.hex(4)}"
    ready = Queue.new
    go = Queue.new
    threads = [4, 9].map do |amount|
      Thread.new do
        Rails.application.executor.wrap do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            go.pop
            @workspace.billing.line(:studio).record_credits(
              amount: amount,
              breakdown: { "kind" => "attempt" },
              idempotency_key: key
            ).id
          end
        end
      end
    end

    ids = Timeout.timeout(15) do
      2.times { ready.pop }
      2.times { go << true }
      threads.map(&:value)
    end

    rows = RecordingStudioStripe::UsageEntry.where(root_recording_id: @root.id, idempotency_key: key)
    assert_equal 1, rows.count
    assert_equal [ids.first], ids.uniq
    assert_includes [4, 9], rows.pick(:quantity)
    assert_equal rows.pick(:quantity), @workspace.billing.line(:studio).meter(:credits).usage
  end
end
