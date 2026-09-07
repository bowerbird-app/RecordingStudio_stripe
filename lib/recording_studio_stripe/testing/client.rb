# frozen_string_literal: true

module RecordingStudioStripe
  module Testing
    StripeObject = Struct.new(
      :id, :object, :url, :mode, :customer, :client_reference_id, :metadata, :status,
      :cancel_at_period_end, :items, :name, :description, :active, :unit_amount, :currency,
      :recurring, :product, :price, :current_period_start, :current_period_end, :data, :type, :email,
      :schedule, :subscription, :phases, :start_date, :end_date, :quantity, :payment_status,
      :automatic_tax, :customer_update, :discounts, keyword_init: true
    ) do
      def [](key)
        public_send(key) if respond_to?(key)
      end
    end

    Event = Struct.new(:id, :type, :data, :created, :livemode, keyword_init: true) do
      def to_hash
        { "id" => id, "type" => type, "created" => created }
      end
    end

    class List
      attr_reader :data

      def initialize(data)
        @data = Array(data)
      end

      def first
        data.first
      end
    end

    class Resource
      def initialize(store)
        @store = store
      end
    end

    class Customers < Resource
      def create(params, _opts = {})
        id = "cus_#{SecureRandom.hex(6)}"
        object = StripeObject.new(id: id, object: "customer", metadata: params[:metadata] || {}, **params.slice(:email))
        @store[:customers][id] = object
        object
      end

      def update(id, params, _opts = {})
        existing = @store[:customers][id] || StripeObject.new(id: id, object: "customer")
        existing.email = params[:email] if params.key?(:email)
        @store[:customers][id] = existing
        existing
      end

      def retrieve(id)
        @store[:customers][id] || StripeObject.new(id: id, object: "customer", metadata: {})
      end
    end

    class CheckoutSessions < Resource
      def create(params, opts = {})
        @store[:checkout_idempotency_keys] << opts[:idempotency_key]
        @store[:last_checkout_params] = params
        id = "cs_#{SecureRandom.hex(6)}"
        object = StripeObject.new(
          id: id,
          object: "checkout.session",
          url: "https://checkout.stripe.test/pay/#{id}",
          mode: params[:mode],
          customer: params[:customer],
          client_reference_id: params[:client_reference_id],
          metadata: params[:metadata] || {},
          status: "open",
          payment_status: "unpaid",
          automatic_tax: params[:automatic_tax],
          customer_update: params[:customer_update]
        )
        @store[:sessions][id] = object
        object
      end

      def retrieve(id)
        @store[:sessions][id] || StripeObject.new(id: id, object: "checkout.session", status: "open")
      end

      def expire(id, _params = {}, _opts = {})
        session = retrieve(id)
        session.status = "expired"
        @store[:sessions][id] = session
        @store[:expired_sessions] << id
        session
      end
    end

    class BillingPortalSessions < Resource
      def create(params, _opts = {})
        raise Stripe::StripeError, "portal is down" if @store[:fail_portal]

        id = "bps_#{SecureRandom.hex(6)}"
        object = StripeObject.new(
          id: id,
          object: "billing_portal.session",
          url: "https://billing.stripe.test/session/#{id}",
          customer: params[:customer]
        )
        @store[:portal_sessions][id] = object
        object
      end
    end

    class BillingPortal
      def initialize(store)
        @store = store
      end

      def sessions
        BillingPortalSessions.new(@store)
      end
    end

    class Subscriptions < Resource
      def retrieve(id)
        @store[:subscriptions][id] || default_subscription(id)
      end

      def update(id, params, _opts = {})
        raise_incomplete!(params)

        existing = retrieve(id)
        existing.status = "active"
        existing.cancel_at_period_end = params[:cancel_at_period_end] if params.key?(:cancel_at_period_end)
        apply_items(existing, params[:items])
        @store[:subscriptions][id] = existing
        existing
      end

      private

      def raise_incomplete!(params)
        return unless params[:payment_behavior] == "error_if_incomplete" && @store[:error_if_incomplete]

        raise Stripe::CardError.new("Your card was declined", "card")
      end

      def apply_items(existing, items)
        return if items.blank?

        item = Array(items).first || {}
        item_id = item[:id].presence || item["id"].presence || "si_#{SecureRandom.hex(4)}"
        price = item[:price] || item["price"]
        existing.items = List.new([StripeObject.new(id: item_id, price: price, quantity: 1)])
      end

      def default_subscription(id)
        StripeObject.new(
          id: id,
          object: "subscription",
          items: List.new([StripeObject.new(id: "si_#{id.delete_prefix('sub_')}", price: nil)]),
          schedule: nil,
          status: "active"
        )
      end
    end

    class SubscriptionSchedules < Resource
      def create(params, _opts = {})
        @store[:schedule_creates] << params
        extra = params.keys.map(&:to_sym) - [:from_subscription]
        if params[:from_subscription] && extra.any?
          raise Stripe::InvalidRequestError.new(
            "When using from_subscription, other parameters cannot be set",
            extra.first.to_s
          )
        end

        now = Time.now.to_i
        id = "sub_sched_#{SecureRandom.hex(6)}"
        object = StripeObject.new(
          id: id,
          object: "subscription_schedule",
          metadata: params,
          phases: [
            StripeObject.new(
              start_date: now,
              end_date: now + 2_592_000,
              items: [StripeObject.new(price: current_price(params[:from_subscription]), quantity: 1)]
            )
          ]
        )
        @store[:schedules][id] = object
        object
      end

      def update(id, params, _opts = {})
        @store[:schedule_updates] << params
        existing = @store[:schedules][id] || StripeObject.new(id: id, object: "subscription_schedule")
        existing.phases = params[:phases] if params.key?(:phases)
        @store[:schedules][id] = existing
        existing
      end

      def release(id, _opts = {})
        StripeObject.new(id: id, object: "subscription_schedule")
      end

      private

      def current_price(subscription_id)
        items = @store[:subscriptions][subscription_id]&.items
        item = items.respond_to?(:first) ? items.first : nil
        item&.price
      end
    end

    class Products < Resource
      def create(params, _opts = {})
        id = "prod_#{SecureRandom.hex(6)}"
        object = StripeObject.new(id: id, object: "product", name: params[:name], description: params[:description],
                                  active: params.fetch(:active, true), metadata: params[:metadata] || {})
        @store[:products][id] = object
        object
      end

      def retrieve(id)
        @store[:products][id] || StripeObject.new(id: id, object: "product", metadata: {})
      end

      def update(id, params, _opts = {})
        existing = retrieve(id)
        existing.name = params[:name] if params.key?(:name)
        existing.description = params[:description] if params.key?(:description)
        existing.metadata = params[:metadata] if params.key?(:metadata)
        existing.active = params[:active] if params.key?(:active)
        @store[:products][id] = existing
        existing
      end

      def list(_params = {})
        List.new(@store[:products].values)
      end
    end

    class Prices < Resource
      def create(params, _opts = {})
        id = "price_#{SecureRandom.hex(6)}"
        recurring = params[:recurring]
        object = StripeObject.new(
          id: id,
          object: "price",
          product: params[:product],
          unit_amount: params[:unit_amount],
          currency: params[:currency],
          recurring: recurring,
          active: params.fetch(:active, true),
          metadata: params[:metadata] || {}
        )
        @store[:prices][id] = object
        object
      end

      def retrieve(id)
        @store[:prices][id] || StripeObject.new(id: id, object: "price", metadata: {})
      end

      def update(id, params, _opts = {})
        existing = retrieve(id)
        existing.metadata = params[:metadata] if params.key?(:metadata)
        existing.active = params[:active] if params.key?(:active)
        @store[:prices][id] = existing
        existing
      end
    end

    class V1
      def initialize(store)
        @store = store
      end

      def customers
        Customers.new(@store)
      end

      def checkout
        self
      end

      def sessions
        CheckoutSessions.new(@store)
      end

      def subscriptions
        Subscriptions.new(@store)
      end

      def subscription_schedules
        SubscriptionSchedules.new(@store)
      end

      def products
        Products.new(@store)
      end

      def prices
        Prices.new(@store)
      end

      def billing_portal
        BillingPortal.new(@store)
      end
    end

    class Client
      def initialize
        @store = {
          customers: {},
          sessions: {},
          subscriptions: {},
          products: {},
          prices: {},
          portal_sessions: {},
          schedules: {},
          schedule_creates: [],
          schedule_updates: [],
          checkout_idempotency_keys: [],
          expired_sessions: [],
          last_checkout_params: nil,
          error_if_incomplete: false,
          fail_portal: false
        }
      end

      def v1
        V1.new(@store)
      end

      def schedule_creates
        @store[:schedule_creates]
      end

      def schedule_updates
        @store[:schedule_updates]
      end

      def checkout_idempotency_keys
        @store[:checkout_idempotency_keys]
      end

      def last_checkout_params
        @store[:last_checkout_params]
      end

      def expired_sessions
        @store[:expired_sessions]
      end

      def fail_incomplete_upgrades!
        @store[:error_if_incomplete] = true
      end

      def fail_portal!
        @store[:fail_portal] = true
      end
    end
  end
end
