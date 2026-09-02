# frozen_string_literal: true

module RecordingStudioStripe
  class ApplySubscription
    def self.call(root_recording:, price:, email: nil, stripe_subscription_id: nil, stripe_customer_id: nil,
                  status: "active", current_period_start: nil, current_period_end: nil, cancel_at_period_end: false)
      new(
        root_recording: root_recording,
        price: price,
        email: email,
        stripe_subscription_id: stripe_subscription_id,
        stripe_customer_id: stripe_customer_id,
        status: status,
        current_period_start: current_period_start,
        current_period_end: current_period_end,
        cancel_at_period_end: cancel_at_period_end
      ).call
    end

    def initialize(root_recording:, price:, email:, stripe_subscription_id:, stripe_customer_id:, status:,
                   current_period_start:, current_period_end:, cancel_at_period_end:)
      @root_recording = root_recording
      @price = price
      @email = email
      @stripe_subscription_id = stripe_subscription_id
      @stripe_customer_id = stripe_customer_id
      @status = status
      @current_period_start = current_period_start
      @current_period_end = current_period_end
      @cancel_at_period_end = cancel_at_period_end
    end

    def call
      customer = find_or_create_customer
      now = Time.current
      period_start = @current_period_start || now
      period_end = @current_period_end || default_period_end(period_start)
      stripe_id = @stripe_subscription_id.presence || "sub_local_#{@root_recording.id.to_s.delete('-')}"

      subscription = Subscription.find_or_initialize_by(stripe_id: stripe_id)
      subscription.assign_attributes(
        root_recording_id: @root_recording.id,
        customer: customer,
        price: @price,
        status: @status,
        cancel_at_period_end: @cancel_at_period_end,
        current_period_start: period_start,
        current_period_end: period_end,
        scheduled_price: next_scheduled_price(subscription)
      )
      subscription.save!
      subscription
    end

    private

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

    def default_period_end(period_start)
      if @price&.annual?
        period_start + 1.year
      else
        period_start + 1.month
      end
    end
  end
end
