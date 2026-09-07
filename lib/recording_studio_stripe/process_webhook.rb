# frozen_string_literal: true

module RecordingStudioStripe
  class ProcessWebhook # rubocop:disable Metrics/ClassLength
    EVENT_HANDLERS = {
      "checkout.session.completed" => :handle_checkout,
      "customer.subscription.created" => :handle_subscription,
      "customer.subscription.updated" => :handle_subscription,
      "customer.subscription.deleted" => :handle_subscription_deleted,
      "invoice.paid" => :handle_invoice_paid,
      "invoice.payment_failed" => :handle_invoice_payment_failed,
      "product.created" => :upsert_product,
      "product.updated" => :upsert_product,
      "product.deleted" => :deactivate_product,
      "price.created" => :handle_price_upsert,
      "price.updated" => :handle_price_upsert,
      "price.deleted" => :deactivate_price
    }.freeze

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
    rescue ActiveRecord::RecordInvalid => e
      raise unless duplicate_event?(e)

      :duplicate
    rescue DeferredWebhook
      :deferred
    end

    private

    def parse_event
      secret = RecordingStudioStripe.configuration.webhook_secret
      if secret.present?
        Stripe::Webhook.construct_event(@payload, @signature, secret)
      elsif RecordingStudioStripe.configuration.local_mode?
        Stripe::Event.construct_from(JSON.parse(@payload))
      else
        raise Stripe::SignatureVerificationError.new(
          "Set STRIPE_WEBHOOK_SECRET when Stripe is configured",
          @signature.to_s
        )
      end
    end

    def event_payload(event)
      event.respond_to?(:to_hash) ? event.to_hash : { "id" => event.id, "type" => event.type }
    end

    def duplicate_event?(error)
      error.record.is_a?(WebhookEvent) && error.record.errors[:stripe_id].any?
    end

    def handle(event)
      method_name = EVENT_HANDLERS[event.type]
      send(method_name, event.data.object) if method_name
    end

    def upsert_product(stripe_product)
      UpsertProduct.call(stripe_product)
    end

    def deactivate_product(stripe_product)
      Product.find_by(stripe_id: stripe_product.id)&.update!(active: false)
    end

    def deactivate_price(stripe_price)
      Price.find_by(stripe_id: stripe_price.id)&.update!(active: false)
    end

    def handle_checkout(session)
      price = price_from_session(session)
      if session.mode == "subscription" || price&.recurring?
        handle_checkout_subscription(session, price)
      else
        handle_checkout_allowance(session, price)
      end
    end

    def handle_checkout_subscription(session, price)
      root = require_root!(root_from(session))
      require_price!(price)
      ApplySubscription.call(
        root_recording: root,
        price: price,
        stripe_subscription_id: stripe_get(session, :subscription),
        stripe_customer_id: stripe_get(session, :customer),
        status: "active"
      )
    end

    def handle_checkout_allowance(session, price)
      root = require_root!(root_from(session))
      require_price!(price)
      ApplyAllowance.call(
        root_recording: root,
        price: price,
        stripe_checkout_session_id: session.id
      )
    end

    def handle_subscription(stripe_subscription)
      root = require_root!(root_from_subscription(stripe_subscription))
      price = require_price!(price_from_subscription(stripe_subscription))
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

    def handle_invoice_paid(invoice)
      subscription = subscription_from_invoice(invoice)
      return if subscription == :none
      return unless subscription.status == "past_due"

      subscription.update!(status: "active")
    end

    def handle_invoice_payment_failed(invoice)
      subscription = subscription_from_invoice(invoice)
      return if subscription == :none

      subscription.update!(status: "past_due")
    end

    def handle_price_upsert(stripe_price)
      product_id = stripe_price_product_id(stripe_price)
      if product_id.present? && Product.find_by(stripe_id: product_id).blank?
        raise DeferredWebhook, "Price product is not in the catalogue yet"
      end

      UpsertPrice.call(stripe_price)
    end

    def stripe_price_product_id(stripe_price)
      product = stripe_get(stripe_price, :product)
      return if product.blank?
      return product if product.is_a?(String)

      stripe_get(product, :id) || product.to_s
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

    def require_root!(root)
      raise DeferredWebhook, "Workspace is not in this app yet" unless root

      root
    end

    def require_price!(price)
      raise DeferredWebhook, "Price is not in the catalogue yet" if price.blank?

      price
    end

    def subscription_from_invoice(invoice)
      stripe_id = invoice_subscription_id(invoice)
      return :none if stripe_id.blank?

      subscription = Subscription.find_by(stripe_id: stripe_id)
      raise DeferredWebhook, "Subscription is not in this app yet" unless subscription

      subscription
    end

    def invoice_subscription_id(invoice)
      parent = stripe_get(invoice, :parent)
      details = stripe_get(parent, :subscription_details)
      value = stripe_get(details, :subscription) || stripe_get(invoice, :subscription)
      return if value.blank?
      return value if value.is_a?(String)

      stripe_get(value, :id) || value.to_s
    end

    def stripe_list_first(list)
      return if list.nil?
      return list.first if list.is_a?(Array)

      stripe_get(list, :data)&.first || (list.respond_to?(:first) ? list.first : nil)
    end

    def stripe_get(object, key)
      return if object.nil?
      return object[key] || object[key.to_s] || object[key.to_sym] if object.is_a?(Hash)

      object.public_send(key)
    rescue NoMethodError
      object[key] || object[key.to_s] if object.is_a?(Hash)
    end

    def timestamp(value)
      return if value.blank?
      return value if value.is_a?(Time)

      Time.zone.at(value.to_i)
    end
  end
end
