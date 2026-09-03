# frozen_string_literal: true

module RecordingStudioStripe
  class ProcessWebhook
    def self.call(payload:, signature:)
      new(payload: payload, signature: signature).call
    end

    def initialize(payload:, signature:)
      @payload = payload
      @signature = signature
    end

    def call
      event = parse_event
      return :duplicate if WebhookEvent.exists?(stripe_id: event.id)

      ApplicationRecord.transaction do
        WebhookEvent.create!(
          stripe_id: event.id,
          event_type: event.type,
          processed_at: Time.current,
          payload: event_payload(event)
        )
        handle(event)
      end
      :processed
    rescue ActiveRecord::RecordNotUnique
      :duplicate
    end

    private

    def parse_event
      secret = RecordingStudioStripe.configuration.webhook_secret
      if secret.present?
        Stripe::Webhook.construct_event(@payload, @signature, secret)
      else
        Stripe::Event.construct_from(JSON.parse(@payload))
      end
    end

    def event_payload(event)
      event.respond_to?(:to_hash) ? event.to_hash : { "id" => event.id, "type" => event.type }
    end

    def handle(event)
      case event.type
      when "checkout.session.completed"
        handle_checkout(event.data.object)
      when "customer.subscription.created", "customer.subscription.updated"
        handle_subscription(event.data.object)
      when "customer.subscription.deleted"
        handle_subscription_deleted(event.data.object)
      when "product.created", "product.updated"
        UpsertProduct.call(event.data.object)
      when "product.deleted"
        Product.find_by(stripe_id: event.data.object.id)&.update!(active: false)
      when "price.created", "price.updated"
        UpsertPrice.call(event.data.object)
      when "price.deleted"
        Price.find_by(stripe_id: event.data.object.id)&.update!(active: false)
      end
    end

    def handle_checkout(session)
      root = root_from(session)
      return unless root

      price = price_from_session(session)
      return unless price
      return if session.mode == "subscription" || price.recurring?

      ApplyAllowance.call(
        root_recording: root,
        price: price,
        stripe_checkout_session_id: session.id
      )
    end

    def handle_subscription(stripe_subscription)
      root = root_from_subscription(stripe_subscription)
      return unless root

      price = price_from_subscription(stripe_subscription)
      item = stripe_list_first(stripe_get(stripe_subscription, :items))
      ApplySubscription.call(
        root_recording: root,
        price: price,
        stripe_subscription_id: stripe_get(stripe_subscription, :id),
        stripe_customer_id: stripe_get(stripe_subscription, :customer),
        status: stripe_get(stripe_subscription, :status),
        current_period_start: timestamp(
          stripe_get(item, :current_period_start) || stripe_get(stripe_subscription, :current_period_start)
        ),
        current_period_end: timestamp(
          stripe_get(item, :current_period_end) || stripe_get(stripe_subscription, :current_period_end)
        ),
        cancel_at_period_end: stripe_get(stripe_subscription, :cancel_at_period_end)
      ).tap do |subscription|
        item_id = stripe_get(item, :id)
        subscription.update!(metadata: subscription.metadata.merge("stripe_item_id" => item_id)) if item_id
      end
    end

    def handle_subscription_deleted(stripe_subscription)
      Subscription.find_by(stripe_id: stripe_subscription.id)&.update!(status: "canceled", cancel_at_period_end: false)
    end

    def root_from(session)
      id = session.metadata&.[]("root_recording_id") || session.client_reference_id
      RecordingStudio::Recording.find_by(id: id)
    end

    def root_from_subscription(stripe_subscription)
      id = stripe_subscription.metadata&.[]("root_recording_id")
      if id.present?
        RecordingStudio::Recording.find_by(id: id)
      else
        Customer.find_by(stripe_id: stripe_subscription.customer)&.root_recording
      end
    end

    def price_from_session(session)
      stripe_price_id = session.metadata&.[]("price_id")
      Price.find_by(stripe_id: stripe_price_id) if stripe_price_id
    end

    def price_from_subscription(stripe_subscription)
      item = stripe_list_first(stripe_get(stripe_subscription, :items))
      price = stripe_get(item, :price)
      stripe_price_id = stripe_get(price, :id) || price
      Price.find_by(stripe_id: stripe_price_id.to_s)
    end

    def stripe_list_first(list)
      stripe_get(list, :data)&.first || (list.respond_to?(:first) ? list.first : nil)
    end

    def stripe_get(object, key)
      return if object.nil?
      return object[key] || object[key.to_s] || object[key.to_sym] if object.is_a?(Hash)

      object.public_send(key)
    rescue NoMethodError
      object[key] || object[key.to_s] if object.respond_to?(:[])
    end

    def timestamp(value)
      return if value.blank?
      return value if value.is_a?(Time)

      Time.zone.at(value.to_i)
    end
  end
end
