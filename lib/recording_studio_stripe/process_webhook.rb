# frozen_string_literal: true

module RecordingStudioStripe
  class ProcessWebhook # rubocop:disable Metrics/ClassLength
    include StripeRequest

    PAID_PAYMENT_STATUSES = %w[paid no_payment_required].freeze

    EVENT_HANDLERS = {
      "checkout.session.completed" => :handle_checkout,
      "checkout.session.async_payment_succeeded" => :handle_checkout,
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
    rescue ActiveRecord::RecordNotUnique => e
      raise unless webhook_event_conflict?(e)

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
      object = stripe_get(stripe_get(event, :data), :object)
      {
        "id" => event.id,
        "type" => event.type,
        "created" => stripe_get(event, :created),
        "object_id" => stripe_get(object, :id),
        "livemode" => stripe_get(event, :livemode)
      }
    end

    def duplicate_event?(error)
      error.record.is_a?(WebhookEvent) && error.record.errors[:stripe_id].any?
    end

    def webhook_event_conflict?(error)
      message = [error.message, error.cause&.message].compact.join("\n")
      message.match?(/webhook_events/i) && message.match?(/stripe_id/i)
    end

    def handle(event)
      method_name = EVENT_HANDLERS[event.type]
      return unless method_name

      object = event.data.object
      created = stripe_get(event, :created)
      if method_name == :handle_subscription
        handle_subscription(object, event_created: created)
      else
        send(method_name, object)
      end
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
      return if stripe_get(session, :status).to_s == "expired"
      return unless checkout_paid?(session)

      price = price_from_session(session)
      if checkout_subscription?(session, price)
        handle_checkout_subscription(session, price)
      else
        handle_checkout_allowance(session, price)
      end
    end

    def checkout_paid?(session)
      PAID_PAYMENT_STATUSES.include?(stripe_get(session, :payment_status).to_s)
    end

    def checkout_subscription?(session, price)
      return true if price&.product&.plan?
      return false if price&.product&.allowance?

      session.mode == "subscription" || price&.recurring?
    end

    def handle_checkout_subscription(session, price)
      root = require_root!(root_from(session))
      require_price!(price)
      stripe_subscription_id = stripe_get(session, :subscription)
      if stripe_subscription_id.blank? && !RecordingStudioStripe.configuration.local_mode?
        raise DeferredWebhook, "Checkout has no Subscription yet"
      end

      ApplySubscription.call(
        root_recording: root,
        price: price,
        stripe_subscription_id: stripe_subscription_id,
        stripe_customer_id: stripe_get(session, :customer),
        status: "active",
        checkout_session_id: stripe_get(session, :id)
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

    def handle_subscription(stripe_subscription, event_created: nil)
      root = require_root!(root_from_subscription(stripe_subscription))
      price = require_price!(price_from_subscription(stripe_subscription))
      item = matching_subscription_item(stripe_subscription, price.stripe_id)
      period_start, period_end = subscription_period(item, stripe_subscription)
      ApplySubscription.call(
        root_recording: root,
        price: price,
        stripe_subscription_id: stripe_get(stripe_subscription, :id),
        stripe_customer_id: stripe_get(stripe_subscription, :customer),
        status: stripe_get(stripe_subscription, :status),
        current_period_start: period_start,
        current_period_end: period_end,
        cancel_at_period_end: stripe_get(stripe_subscription, :cancel_at_period_end),
        stripe_event_created: event_created
      ).tap { |subscription| store_item_id(subscription, item, event_created) }
    end

    def subscription_period(item, stripe_subscription)
      [
        timestamp(stripe_get(item, :current_period_start) || stripe_get(stripe_subscription, :current_period_start)),
        timestamp(stripe_get(item, :current_period_end) || stripe_get(stripe_subscription, :current_period_end))
      ]
    end

    def store_item_id(subscription, item, event_created)
      item_id = stripe_get(item, :id)
      return if item_id.blank?
      return if event_created.present? && subscription.metadata.to_h["stripe_event_created"].to_s != event_created.to_s

      subscription.update!(metadata: subscription.metadata.merge("stripe_item_id" => item_id))
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
      item = matching_subscription_item(stripe_subscription)
      stripe_price_id = item_price_id(item)
      Price.find_by(stripe_id: stripe_price_id.to_s) if stripe_price_id
    end

    def matching_subscription_item(stripe_subscription, preferred_price_id = nil)
      items = stripe_list_items(stripe_get(stripe_subscription, :items))
      if preferred_price_id.present?
        match = items.find { |item| item_price_id(item) == preferred_price_id.to_s }
        return match if match
      end
      items.first
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

    def timestamp(value)
      return if value.blank?
      return value if value.is_a?(Time)

      Time.zone.at(value.to_i)
    end
  end
end
