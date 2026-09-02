# frozen_string_literal: true

module RecordingStudioStripe
  module Testing
    StripeObject = Struct.new(
      :id, :object, :url, :mode, :customer, :client_reference_id, :metadata, :status,
      :cancel_at_period_end, :items, :name, :description, :active, :unit_amount, :currency,
      :recurring, :product, :current_period_start, :current_period_end, :data, :type,
      keyword_init: true
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
    end

    class Resource
      def initialize(store)
        @store = store
      end
    end

    class Customers < Resource
      def create(params)
        id = "cus_#{SecureRandom.hex(6)}"
        object = StripeObject.new(id: id, object: "customer", metadata: params[:metadata] || {}, **params.slice(:email))
        @store[:customers][id] = object
        object
      end
    end

    class CheckoutSessions < Resource
      def create(params)
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

    class Subscriptions < Resource
      def update(id, params)
        existing = @store[:subscriptions][id] || StripeObject.new(id: id, object: "subscription", items: List.new([]))
        existing.status = "active"
        existing.cancel_at_period_end = params[:cancel_at_period_end] if params.key?(:cancel_at_period_end)
        @store[:subscriptions][id] = existing
        existing
      end
    end

    class SubscriptionSchedules < Resource
      def create(params)
        id = "sub_sched_#{SecureRandom.hex(6)}"
        StripeObject.new(id: id, object: "subscription_schedule", metadata: params)
      end
    end

    class Products < Resource
      def create(params)
        id = "prod_#{SecureRandom.hex(6)}"
        object = StripeObject.new(id: id, object: "product", name: params[:name], description: params[:description],
                                  active: params.fetch(:active, true), metadata: params[:metadata] || {})
        @store[:products][id] = object
        object
      end

      def list(_params = {})
        List.new(@store[:products].values)
      end
    end

    class Prices < Resource
      def create(params)
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
    end

    class Client
      def initialize
        @store = { customers: {}, sessions: {}, subscriptions: {}, products: {}, prices: {} }
      end

      def v1
        V1.new(@store)
      end
    end
  end
end
