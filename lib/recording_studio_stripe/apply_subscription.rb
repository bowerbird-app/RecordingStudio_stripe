# frozen_string_literal: true

module RecordingStudioStripe
  class ApplySubscription
    def self.call(root_recording:, price:, email: nil, stripe_subscription_id: nil, stripe_customer_id: nil,
                  status: "active", current_period_start: nil, current_period_end: nil, cancel_at_period_end: false,
                  stripe_event_created: nil, checkout_session_id: nil)
      new(
        root_recording: root_recording,
        price: price,
        email: email,
        stripe_subscription_id: stripe_subscription_id,
        stripe_customer_id: stripe_customer_id,
        status: status,
        current_period_start: current_period_start,
        current_period_end: current_period_end,
        cancel_at_period_end: cancel_at_period_end,
        stripe_event_created: stripe_event_created,
        checkout_session_id: checkout_session_id
      ).call
    end

    def initialize(root_recording:, price:, email:, stripe_subscription_id:, stripe_customer_id:, status:,
                   current_period_start:, current_period_end:, cancel_at_period_end:, stripe_event_created:,
                   checkout_session_id:)
      @root_recording = root_recording
      @price = price
      @email = email
      @stripe_subscription_id = stripe_subscription_id
      @stripe_customer_id = stripe_customer_id
      @status = status
      @current_period_start = current_period_start
      @current_period_end = current_period_end
      @cancel_at_period_end = cancel_at_period_end
      @stripe_event_created = stripe_event_created
      @checkout_session_id = checkout_session_id
    end

    def call
      customer = find_or_create_customer
      now = Time.current
      type = SubscriptionTypes.normalize(@price&.product&.subscription_type)
      stripe_id = resolve_stripe_id(type)

      subscription = find_subscription(stripe_id, type)
      return subscription if stale_event?(subscription)

      period_start = resolve_period_start(subscription, now)
      period_end = resolve_period_end(subscription, period_start)
      subscription.assign_attributes(
        stripe_id: stripe_id,
        root_recording_id: @root_recording.id,
        customer: customer,
        price: @price,
        subscription_type: type,
        status: @status,
        cancel_at_period_end: @cancel_at_period_end,
        current_period_start: period_start,
        current_period_end: period_end,
        scheduled_price: next_scheduled_price(subscription),
        metadata: merged_metadata(subscription)
      )
      subscription.save!
      subscription
    end

    private

    def resolve_stripe_id(type)
      return @stripe_subscription_id if @stripe_subscription_id.present?

      unless RecordingStudioStripe.configuration.local_mode?
        raise ArgumentError, "stripe_subscription_id is required when Stripe is configured"
      end

      "sub_local_#{@root_recording.id.to_s.delete('-')}_#{type}"
    end

    def find_subscription(stripe_id, type)
      Subscription.find_by(stripe_id: stripe_id) ||
        pending_checkout(type) ||
        Subscription.current_for(root_recording_id: @root_recording.id, subscription_type: type) ||
        Subscription.new(stripe_id: stripe_id)
    end

    def pending_checkout(type)
      scope = Subscription.where(
        root_recording_id: @root_recording.id,
        subscription_type: type,
        status: %w[incomplete incomplete_expired]
      )
      ordered = scope.order(created_at: :desc)
      if @checkout_session_id.present?
        match = ordered.find { |row| row.metadata.to_h["checkout_session_id"] == @checkout_session_id }
        return match if match
      end
      ordered.first
    end

    def stale_event?(subscription)
      return false unless subscription.persisted?

      created = @stripe_event_created.to_i
      previous = subscription.metadata.to_h["stripe_event_created"].to_i
      created.positive? && previous.positive? && created < previous
    end

    def merged_metadata(subscription)
      data = stringify_metadata(subscription.metadata)
      data["stripe_event_created"] = @stripe_event_created.to_s if @stripe_event_created.present?
      data["checkout_session_id"] = @checkout_session_id if @checkout_session_id.present?
      data
    end

    def stringify_metadata(metadata)
      return {} if metadata.blank?

      metadata.to_h.stringify_keys
    end

    def find_or_create_customer
      if @stripe_customer_id.present?
        Customer.find_or_initialize_by(stripe_id: @stripe_customer_id).tap do |customer|
          customer.root_recording_id ||= @root_recording.id
          customer.email = @email if @email.present?
          customer.save!
        end
      else
        EnsureCustomer.call(root_recording: @root_recording, email: @email)
      end
    end

    def next_scheduled_price(subscription)
      return unless subscription.persisted?
      return if @price&.id == subscription.scheduled_price_id
      return subscription.scheduled_price if @price&.id == subscription.price_id

      nil
    end

    def resolve_period_start(subscription, now)
      @current_period_start || (subscription.persisted? && subscription.current_period_start) || now
    end

    def resolve_period_end(subscription, period_start)
      @current_period_end ||
        (subscription.persisted? && subscription.current_period_end) ||
        default_period_end(period_start)
    end

    def default_period_end(period_start)
      if @price&.annual?
        period_start + 1.year
      else
        period_start + 1.month
      end
    end
  end
end
