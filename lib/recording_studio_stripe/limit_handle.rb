# frozen_string_literal: true

module RecordingStudioStripe
  class LimitHandle
    attr_reader :root_recording, :name, :subscription_type

    def initialize(root_recording:, name:, subscription_type: nil)
      @root_recording = root_recording
      @definition = Limits.fetch(name)
      @name = @definition.name
      @subscription_type = subscription_type.presence || @definition.subscription_type
    end

    def label
      @definition.label
    end

    def aggregation
      @definition.aggregation
    end

    def count?
      @definition.count?
    end

    def quantity?
      @definition.quantity?
    end

    def per_item?
      @definition.per_item?
    end

    def recordable_type
      @definition.recordable_type
    end

    def unit
      @definition.unit
    end

    def display_quantity(quantity)
      @definition.display_quantity(quantity)
    end

    def included
      product = self.product
      return product.limit_quantity(name) if product&.plan?
      return 0 if per_item?

      @definition.no_plan_limit || 0
    end

    def ceiling
      reject_unless_per_item!(:ceiling)
      plan = product
      return @definition.no_plan_limit unless plan&.plan?

      raw_ceiling(plan)
    end

    def allows?(amount)
      reject_unless_per_item!(:allows?)
      value = positive_quantity(amount)
      cap = ceiling
      cap.nil? || value <= cap
    end

    def enforce_item!(amount)
      reject_unless_per_item!(:enforce_item!)
      raise PlanLimitReached.new(handle: self) unless allows?(amount)
    end

    def used
      reject_per_item!
      return 0 if root_recording.blank?

      count? ? live_recordings.count : quantity_used
    end

    def remaining
      reject_per_item!
      [included - used, 0].max
    end

    def available?(quantity = 1)
      reject_per_item!
      amount = positive_quantity(quantity)
      remaining >= amount
    end

    def over?
      reject_per_item!
      used > included
    end

    def enforce!(quantity)
      reject_per_item!
      raise ArgumentError, "enforce! checks capacity. Use with_capacity! to write inside the lock." if block_given?

      with_capacity!(quantity) { true }
    end

    def with_capacity!(quantity)
      reject_per_item!
      raise ArgumentError, "with_capacity! needs a block" unless block_given?

      amount = positive_quantity(quantity)
      raise ArgumentError, "A root recording is required to enforce #{name}" if root_recording.blank?

      root_recording.class.transaction do
        AdvisoryLock.hold(root_recording.class.connection, lock_name)
        raise PlanLimitReached.new(handle: self) unless available?(amount)

        yield
      end
    end

    def product
      subscription&.price&.product
    end

    def subscription
      return if root_recording.blank?

      @subscription ||= Subscription.current_for(
        root_recording_id: root_recording.id,
        subscription_type: subscription_type
      )
    end

    private

    def live_recordings
      scope = RecordingStudio::Recording.for_root(root_recording.id).of_type(recordable_type)
      return scope unless RecordingStudio::Recording.column_names.include?("trashed_at")

      scope.where(trashed_at: nil)
    end

    def quantity_used
      provider = RecordingStudioStripe.configuration.limit_usage_for(name)
      raise ArgumentError, missing_usage_message unless provider

      value = provider.call(root_recording)
      return value if value.is_a?(Integer) && value >= 0

      raise ArgumentError, "Limit #{name} usage must be a non-negative integer, got #{value.inspect}"
    end

    def missing_usage_message
      "No usage provider registered for limit #{name}. " \
        "Call RecordingStudioStripe.register_limit_usage(#{name.to_sym.inspect})."
    end

    def positive_quantity(quantity)
      return quantity if quantity.is_a?(Integer) && quantity.positive?

      raise ArgumentError, "quantity must be a positive integer"
    end

    def reject_per_item!
      return unless per_item?

      raise ArgumentError, "#{name} is a per-item ceiling. Use ceiling or enforce_item!."
    end

    def reject_unless_per_item!(method_name)
      return if per_item?

      raise ArgumentError, "#{method_name} is for a per-item ceiling. #{name} is a #{aggregation} limit."
    end

    def raw_ceiling(plan)
      raw = plan.metadata.to_h.stringify_keys["limit_#{name}"]
      return if raw.nil? || raw.to_s.strip.empty?

      Integer(raw, exception: false)
    end

    def lock_name
      return "#{root_recording.id}:#{recordable_type}" if count?

      "#{root_recording.id}:limit:#{name}"
    end
  end
end
