# frozen_string_literal: true

module RecordingStudioStripe
  module Testing
    StripeObject = Struct.new(
      :id, :object, :url, :mode, :customer, :client_reference_id, :metadata, :status,
      :cancel_at_period_end, :items, :name, :description, :active, :unit_amount, :currency,
      :recurring, :product, :price, :current_period_start, :current_period_end, :data, :type, :email,
      :schedule, :subscription, keyword_init: true
    ) do
      def [](key)
        public_send(key) if respond_to?(key)
      end
    end

    Event = Struct.new(:id, :type, :data, keyword_init: true) do
      def to_hash
        { "id" => id, "type" => type }
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
      def create(params, _opts = {})
        id = "cs_#{SecureRandom.hex(6)}"
        object = StripeObject.new(
          id: id,
          object: "checkout.session",
          url: "https://checkout.stripe.test/pay/#{id}",
          mode: params[:mode],
          customer: params[:customer],
          client_reference_id: params[:client_reference_id],
          metadata: params[:metadata] || {}
        )
        @store[:sessions][id] = object
        object
      end
    end

    class BillingPortalSessions < Resource
      def create(params, _opts = {})
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
        existing = retrieve(id)
        existing.status = "active"
        existing.cancel_at_period_end = params[:cancel_at_period_end] if params.key?(:cancel_at_period_end)
        if params[:items]
          item = Array(params[:items]).first || {}
          item_id = item[:id].presence || item["id"].presence || "si_#{SecureRandom.hex(4)}"
          price = item[:price] || item["price"]
          existing.items = List.new([StripeObject.new(id: item_id, price: price)])
        end
        @store[:subscriptions][id] = existing
        existing
      end

      private

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
        id = "sub_sched_#{SecureRandom.hex(6)}"
        StripeObject.new(id: id, object: "subscription_schedule", metadata: params)
      end

      def release(id, _opts = {})
        StripeObject.new(id: id, object: "subscription_schedule")
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
        @store = { customers: {}, sessions: {}, subscriptions: {}, products: {}, prices: {}, portal_sessions: {} }
      end

      def v1
        V1.new(@store)
      end
    end
  end
end
