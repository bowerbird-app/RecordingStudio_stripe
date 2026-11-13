# frozen_string_literal: true

module RecordingStudioStripe
  class PlanDowngrade
    def self.record!(subscription:, previous:)
      new(subscription, previous).record!
    end

    def self.rebuild!(webhook_event)
      snapshot = webhook_event.payload.to_h["plan_downgrade"]
      return if snapshot.blank?

      subscription = Subscription.find_by(id: snapshot["subscription_id"])
      return unless subscription

      store_event(
        webhook_event,
        subscription,
        "plan_downgraded/#{webhook_event.stripe_id}",
        snapshot.except("subscription_id")
      )
    end

    def self.store_event(webhook_event, subscription, idempotency_key, payload)
      DomainEvents.with_webhook(webhook_event) do
        DomainEvents.send(
          :create_event,
          name: "plan_downgraded",
          idempotency_key: idempotency_key,
          subscription: subscription,
          payload: payload
        )
      end
    end
    private_class_method :store_event

    def initialize(subscription, previous)
      @subscription = subscription
      @previous = previous
    end

    def record!
      return unless DomainEvents.events_table?

      webhook = DomainEvents.send(:current_webhook)
      return if webhook.blank? || @subscription.blank? || @previous.blank? || @previous[:status] == "canceled"

      payload = event_payload
      return if payload.blank?

      remember(webhook, payload)
      self.class.send(:store_event, webhook, @subscription, "plan_downgraded/#{webhook.stripe_id}", payload)
    end

    private

    def remember(webhook, payload)
      snapshot = payload.merge("subscription_id" => @subscription.id)
      webhook.update!(payload: webhook.payload.merge("plan_downgrade" => snapshot))
    end

    def event_payload
      old_product = @previous[:product]
      return if old_product.blank?
      return if same_product?

      loss = PlanLoss.new(
        from_product: old_product,
        to_product: new_product,
        subscription_type: @subscription.subscription_type
      )
      return unless loss.loss?

      {
        "subscription_type" => @subscription.subscription_type,
        "old_product_id" => old_product.id,
        "old_product_name" => old_product.name,
        "new_product_id" => new_product&.id,
        "new_product_name" => new_product&.name,
        "paywalls_lost" => loss.paywalls_lost,
        "limits_lowered" => limit_rows(loss),
        "reason" => ended? ? "canceled" : "downgrade",
        "timing" => timing,
        "effective_at" => effective_at
      }
    end

    def same_product?
      return false if ended?

      new_product.blank? || new_product.id == @previous[:product].id
    end

    def new_product
      return if ended?

      @subscription.price&.product
    end

    def ended?
      @subscription.status == "canceled"
    end

    def timing
      return cancel_timing if ended?
      return "at_period_end" if scheduled_match?

      "immediately"
    end

    def cancel_timing
      return "at_period_end" if @previous[:cancel_at_period_end]

      "immediately"
    end

    def scheduled_match?
      scheduled_id = @previous[:scheduled_price_id]
      scheduled_id.present? && scheduled_id == @subscription.price_id
    end

    def limit_rows(loss)
      loss.limits_lowered.map do |row|
        { "name" => row[:name], "from" => row[:from], "to" => row[:to] }
      end
    end

    def effective_at
      DomainEvents.send(:occurred_at).utc.iso8601
    end
  end
end
