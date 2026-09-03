# frozen_string_literal: true

module RecordingStudioStripe
  module Admin
    module Definitions
      module_function

      def ensure!
        return if defined?(StripeSection)

        stripe_section
        products_screen
        prices_screen
        meters_screen
        paywalls_screen
        customers_screen
        subscriptions_screen
        widgets
      end

      def stripe_section
        klass = Class.new(RecordingStudioAdmin::Section)
        klass.key "stripe"
        klass.icon :credit_card
        klass.title "Stripe"
        klass.subtitle "Products, Prices, meters, paywalls, and who is paying"
        klass.blast_radius :site
        klass.link :products, text: "Products", url: ->(context) { context.admin_screen_path("products") }
        klass.link :prices, text: "Prices", url: ->(context) { context.admin_screen_path("prices") }
        klass.link :meters, text: "Meters", url: ->(context) { context.admin_screen_path("meters") }
        klass.link :paywalls, text: "Paywalls", url: ->(context) { context.admin_screen_path("paywalls") }
        klass.link :customers, text: "Customers", url: ->(context) { context.admin_screen_path("customers") }
        klass.link :subscriptions,
                   text: "Subscriptions",
                   url: ->(context) { context.admin_screen_path("subscriptions") }
        klass.widget "widgets.stripe.past_due"
        klass.widget "widgets.stripe.active_subscriptions"
        RecordingStudioStripe::Admin::Definitions.const_set(:StripeSection, klass)
      end

      def products_screen
        klass = Class.new(RecordingStudioAdmin::Screen)
        klass.key "products"
        klass.icon :cube
        klass.title "Products"
        klass.subtitle "One Product per plan. Extra packs are Products too."
        klass.blast_radius :site
        klass.query { |_context| RecordingStudioStripe::Product.includes(:paywalls).order(:name) }
        klass.button :new_product,
                     text: "New Product",
                     url: ->(_context) { "#{RecordingStudioStripe.configuration.mount_path}/admin/products/new" }
        klass.table do
          column :name
          column :kind
          column :opens,
                 title: "Opens",
                 sortable: false,
                 value: ->(row, _context) { row.opens_labels.join(", ").presence || "—" }
          column :active
          column :stripe_id
          action :edit,
                 text: "Edit",
                 url: lambda { |row, _context|
                   "#{RecordingStudioStripe.configuration.mount_path}/admin/products/#{row.id}/edit"
                 }
          action :add_price,
                 text: "Add Price",
                 url: lambda { |row, _context|
                   "#{RecordingStudioStripe.configuration.mount_path}/admin/prices/new?product_id=#{row.id}"
                 }
        end
        RecordingStudioStripe::Admin::Definitions.const_set(:ProductsScreen, klass)
      end

      def prices_screen
        klass = Class.new(RecordingStudioAdmin::Screen)
        klass.key "prices"
        klass.icon :banknotes
        klass.title "Prices"
        klass.subtitle "Monthly, yearly, and one-time Prices, grouped under a Product"
        klass.blast_radius :site
        klass.query { |_context| RecordingStudioStripe::Admin::Definitions.prices_relation }
        klass.filter :product,
                     options: -> { RecordingStudioStripe::Product.order(:name).pluck(:name) },
                     apply: lambda { |relation, value, _context|
                       relation.where(recording_studio_stripe_products: { name: value })
                     }
        klass.filter :interval, options: %w[month year]
        klass.table do
          column :product, sortable: false, value: ->(row, _context) { row.product.name }
          column :interval
          column :unit_amount
          column :currency
          column :active
          column :stripe_id
        end
        RecordingStudioStripe::Admin::Definitions.const_set(:PricesScreen, klass)
      end

      def prices_relation
        RecordingStudioStripe::Price.includes(:product).joins(:product).merge(
          RecordingStudioStripe::Product.order(:name)
        ).order(:interval, :unit_amount)
      end

      def meters_screen
        klass = Class.new(RecordingStudioAdmin::Screen)
        klass.key "meters"
        klass.icon :chart_bar
        klass.title "Meters"
        klass.subtitle "Named usage counters the app records against"
        klass.blast_radius :site
        klass.query { |_context| RecordingStudioStripe::Meter.order(:name) }
        klass.button :new_meter,
                     text: "New Meter",
                     url: ->(_context) { "#{RecordingStudioStripe.configuration.mount_path}/admin/meters/new" }
        klass.table do
          column :name
          column :label
          column :stripe_meter_id
        end
        RecordingStudioStripe::Admin::Definitions.const_set(:MetersScreen, klass)
      end

      def paywalls_screen
        klass = Class.new(RecordingStudioAdmin::Screen)
        klass.key "paywalls"
        klass.icon :lock_closed
        klass.title "Paywalls"
        klass.subtitle "Named things a plan can open. Tick them on the Product."
        klass.blast_radius :site
        klass.query { |_context| RecordingStudioStripe::Paywall.order(:name) }
        klass.button :new_paywall,
                     text: "New paywall",
                     url: ->(_context) { "#{RecordingStudioStripe.configuration.mount_path}/admin/paywalls/new" }
        klass.table do
          column :name
          column :label
        end
        RecordingStudioStripe::Admin::Definitions.const_set(:PaywallsScreen, klass)
      end

      def customers_screen
        klass = Class.new(RecordingStudioAdmin::Screen)
        klass.key "customers"
        klass.icon :users
        klass.title "Customers"
        klass.subtitle "Stripe Customers tied to a workspace"
        klass.blast_radius :site
        klass.query { |_context| RecordingStudioStripe::Customer.order(created_at: :desc) }
        klass.table do
          column :stripe_id
          column :email
          column :root_recording_id
        end
        RecordingStudioStripe::Admin::Definitions.const_set(:CustomersScreen, klass)
      end

      def subscriptions_screen
        klass = Class.new(RecordingStudioAdmin::Screen)
        klass.key "subscriptions"
        klass.icon :arrow_path
        klass.title "Subscriptions"
        klass.subtitle "What Stripe says is current"
        klass.blast_radius :site
        klass.query { |_context| RecordingStudioStripe::Subscription.includes(:price, :customer).order(updated_at: :desc) }
        klass.table do
          column :stripe_id
          column :status
          column :cancel_at_period_end
          column :current_period_end
        end
        RecordingStudioStripe::Admin::Definitions.const_set(:SubscriptionsScreen, klass)
      end

      def widgets
        past_due = RecordingStudioAdmin::Widget.new("widgets.stripe.past_due") do
          type :number
          title "Past due"
          info "Subscriptions Stripe marked past_due. Someone probably needs a card update."
          blast_radius :site
          hide_change
          hide_period
          value { |_context| RecordingStudioStripe::Subscription.where(status: "past_due").count }
          link_to { |context| context.admin_screen_path("subscriptions") }
        end
        active = RecordingStudioAdmin::Widget.new("widgets.stripe.active_subscriptions") do
          type :number
          title "Active subscriptions"
          info "active and trialing. Past due is a separate card."
          blast_radius :site
          hide_change
          hide_period
          value { |_context| RecordingStudioStripe::Subscription.where(status: %w[active trialing]).count }
          link_to { |context| context.admin_screen_path("subscriptions") }
        end
        RecordingStudioStripe::Admin::Definitions.const_set(:PastDueWidget, past_due)
        RecordingStudioStripe::Admin::Definitions.const_set(:ActiveSubscriptionsWidget, active)
      end
    end
  end
end
