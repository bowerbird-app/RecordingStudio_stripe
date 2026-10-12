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

      # rubocop:disable Metrics/AbcSize
      def stripe_section
        klass = Class.new(RecordingStudioAdmin::Section)
        klass.key "stripe"
        klass.icon :credit_card
        # Titles/links resolve via evaluate/resolve at render. Subtitles stay English
        # literals — Admin search reads screen_definition.subtitle raw.
        klass.title { Copy.t("admin.definitions.section.title", default: "Stripe") }
        klass.subtitle "Products, Prices, meters, paywalls, and who is paying"
        klass.blast_radius :site
        klass.link :products,
                   text: ->(_context) { Copy.t("admin.definitions.section.link_products", default: "Products") },
                   url: ->(context) { context.admin_screen_path("products") }
        klass.link :prices,
                   text: ->(_context) { Copy.t("admin.definitions.section.link_prices", default: "Prices") },
                   url: ->(context) { context.admin_screen_path("prices") }
        klass.link :meters,
                   text: ->(_context) { Copy.t("admin.definitions.section.link_meters", default: "Meters") },
                   url: ->(context) { context.admin_screen_path("meters") }
        klass.link :paywalls,
                   text: ->(_context) { Copy.t("admin.definitions.section.link_paywalls", default: "Paywalls") },
                   url: ->(context) { context.admin_screen_path("paywalls") }
        klass.link :customers,
                   text: ->(_context) { Copy.t("admin.definitions.section.link_customers", default: "Customers") },
                   url: ->(context) { context.admin_screen_path("customers") }
        klass.link :subscriptions,
                   text: ->(_context) { Copy.t("admin.definitions.section.link_subscriptions", default: "Subscriptions") }, # rubocop:disable Layout/LineLength
                   url: ->(context) { context.admin_screen_path("subscriptions") }
        klass.widget "widgets.stripe.past_due"
        klass.widget "widgets.stripe.active_subscriptions"
        RecordingStudioStripe::Admin::Definitions.const_set(:StripeSection, klass)
      end
      # rubocop:enable Metrics/AbcSize

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def products_screen
        klass = Class.new(RecordingStudioAdmin::Screen)
        klass.key "products"
        klass.icon :cube
        klass.title { Copy.t("admin.definitions.products.title", default: "Products") }
        klass.subtitle "One Product per plan. Extra packs are Products too."
        klass.blast_radius :site
        klass.query { |_context| RecordingStudioStripe::Product.includes(:paywalls).order(:name) }
        klass.button :new_product,
                     text: ->(_context) { Copy.t("admin.definitions.products.new_button", default: "New Product") },
                     url: ->(_context) { "#{RecordingStudioStripe.configuration.mount_path}/admin/products/new" }
        klass.table do
          column :name
          column :kind
          column :plan_group,
                 title: "Plan group",
                 sortable: false,
                 value: ->(row, _context) { row.plan? ? row.subscription_type_label : "—" }
          column :opens,
                 title: "Opens",
                 sortable: false,
                 value: ->(row, _context) { row.opens_labels.join(", ").presence || "—" }
          column :active
          column :stripe_id
          action :edit,
                 text: ->(_row, _context) { Copy.t("admin.definitions.products.edit", default: "Edit") },
                 url: lambda { |row, _context|
                   "#{RecordingStudioStripe.configuration.mount_path}/admin/products/#{row.id}/edit"
                 }
          action :add_price,
                 text: ->(_row, _context) { Copy.t("admin.definitions.products.add_price", default: "Add Price") },
                 url: lambda { |row, _context|
                   "#{RecordingStudioStripe.configuration.mount_path}/admin/prices/new?product_id=#{row.id}"
                 }
        end
        RecordingStudioStripe::Admin::Definitions.const_set(:ProductsScreen, klass)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      # rubocop:disable Metrics/AbcSize
      def prices_screen
        klass = Class.new(RecordingStudioAdmin::Screen)
        klass.key "prices"
        klass.icon :banknotes
        klass.title { Copy.t("admin.definitions.prices.title", default: "Prices") }
        klass.subtitle "Weekly, monthly, yearly, and one-time Prices, grouped under a Product"
        klass.blast_radius :site
        klass.query { |_context| RecordingStudioStripe::Admin::Definitions.prices_relation }
        klass.filter :product,
                     options: -> { RecordingStudioStripe::Product.order(:name).pluck(:name) },
                     apply: lambda { |relation, value, _context|
                       relation.where(recording_studio_stripe_products: { name: value })
                     }
        klass.filter :interval, options: %w[week month year]
        klass.table do
          column :product, sortable: false, value: ->(row, _context) { row.product.name }
          column :interval
          column :unit_amount
          column :currency
          column :active
          column :stripe_id
          action :edit,
                 text: ->(_row, _context) { Copy.t("admin.definitions.prices.edit", default: "Edit") },
                 url: lambda { |row, _context|
                   "#{RecordingStudioStripe.configuration.mount_path}/admin/prices/#{row.id}/edit"
                 }
        end
        RecordingStudioStripe::Admin::Definitions.const_set(:PricesScreen, klass)
      end
      # rubocop:enable Metrics/AbcSize

      def prices_relation
        RecordingStudioStripe::Price.includes(:product).joins(:product).merge(
          RecordingStudioStripe::Product.order(:name)
        ).order(:interval, :unit_amount)
      end

      def meters_screen
        klass = Class.new(RecordingStudioAdmin::Screen)
        klass.key "meters"
        klass.icon :chart_bar
        klass.title { Copy.t("admin.definitions.meters.title", default: "Meters") }
        klass.subtitle "Named usage counters the app records against"
        klass.blast_radius :site
        klass.query { |_context| RecordingStudioStripe::Meter.order(:name) }
        klass.button :new_meter,
                     text: ->(_context) { Copy.t("admin.definitions.meters.new_button", default: "New Meter") },
                     url: ->(_context) { "#{RecordingStudioStripe.configuration.mount_path}/admin/meters/new" }
        klass.table do
          column :name
          column :label
        end
        RecordingStudioStripe::Admin::Definitions.const_set(:MetersScreen, klass)
      end

      def paywalls_screen
        klass = Class.new(RecordingStudioAdmin::Screen)
        klass.key "paywalls"
        klass.icon :lock_closed
        klass.title { Copy.t("admin.definitions.paywalls.title", default: "Paywalls") }
        klass.subtitle "Named things a plan can open. Tick them on the Product."
        klass.blast_radius :site
        klass.query { |_context| RecordingStudioStripe::Paywall.order(:name) }
        klass.button :new_paywall,
                     text: ->(_context) { Copy.t("admin.definitions.paywalls.new_button", default: "New paywall") },
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
        klass.title { Copy.t("admin.definitions.customers.title", default: "Customers") }
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
        klass.title { Copy.t("admin.definitions.subscriptions.title", default: "Subscriptions") }
        klass.subtitle "What Stripe says is current"
        klass.blast_radius :site
        klass.query { |_context| RecordingStudioStripe::Subscription.includes(:price, :customer).order(updated_at: :desc) }
        klass.table do
          column :stripe_id
          column :subscription_type,
                 title: "Plan group",
                 sortable: false,
                 value: ->(row, _context) { row.subscription_type_label }
          column :status
          column :cancel_at_period_end
          column :current_period_end
        end
        RecordingStudioStripe::Admin::Definitions.const_set(:SubscriptionsScreen, klass)
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def widgets
        past_due = RecordingStudioAdmin::Widget.new("widgets.stripe.past_due") do
          type :number
          title { Copy.t("admin.definitions.widgets.past_due_title", default: "Past due") }
          info do
            Copy.t(
              "admin.definitions.widgets.past_due_info",
              default: "Subscriptions Stripe marked past_due. Someone probably needs a card update."
            )
          end
          blast_radius :site
          hide_change
          hide_period
          value { |_context| RecordingStudioStripe::Subscription.where(status: "past_due").count }
          link_to { |context| context.admin_screen_path("subscriptions") }
        end
        active = RecordingStudioAdmin::Widget.new("widgets.stripe.active_subscriptions") do
          type :number
          title { Copy.t("admin.definitions.widgets.active_title", default: "Active subscriptions") }
          info do
            Copy.t(
              "admin.definitions.widgets.active_info",
              default: "active and trialing. Past due is a separate card."
            )
          end
          blast_radius :site
          hide_change
          hide_period
          value { |_context| RecordingStudioStripe::Subscription.where(status: %w[active trialing]).count }
          link_to { |context| context.admin_screen_path("subscriptions") }
        end
        RecordingStudioStripe::Admin::Definitions.const_set(:PastDueWidget, past_due)
        RecordingStudioStripe::Admin::Definitions.const_set(:ActiveSubscriptionsWidget, active)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    end
  end
end
