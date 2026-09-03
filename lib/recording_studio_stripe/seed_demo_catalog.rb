# frozen_string_literal: true

module RecordingStudioStripe
  class SeedDemoCatalog
    DEMO_METADATA_KEY = "recording_studio_demo"

    def self.call
      new.call
    end

    def call
      Meter.sync_from_config!
      Paywall.sync_from_config!
      starter = upsert_product("Starter", "plan", "A quiet start.")
      pro = upsert_product("Pro", "plan", "The usual working plan.")
      tokens = upsert_product("AI token packs", "allowance", "Extra AI tokens for this period.")
      pro.assign_paywalls(%w[generate_image])
      RegisterPaywallActions.call

      upsert_price(starter, 900, "month", { "included_ai_tokens" => "1000000", "included_api_calls" => "10000" })
      upsert_price(starter, 9000, "year", { "included_ai_tokens" => "1000000", "included_api_calls" => "10000" })
      upsert_price(pro, 2900, "month", { "included_ai_tokens" => "10000000", "included_api_calls" => "100000" })
      upsert_price(pro, 29_000, "year", { "included_ai_tokens" => "10000000", "included_api_calls" => "100000" })
      upsert_price(tokens, 1000, nil, { "meter" => "ai_tokens", "allowance" => "5000000" })
      upsert_price(tokens, 3000, nil, { "meter" => "ai_tokens", "allowance" => "20000000" })
    end

    private

    def upsert_product(name, kind, description)
      product = Product.find_or_initialize_by(name: name, kind: kind)
      product.description = description
      product.active = true
      product.metadata = { "kind" => kind, DEMO_METADATA_KEY => demo_key(name) }
      product.stripe_id = stripe_product_id(product, name, kind, description)
      product.save!
      product
    end

    def upsert_price(product, unit_amount, interval, metadata)
      price = product.prices.find_or_initialize_by(unit_amount: unit_amount, interval: interval)
      price.currency = "usd"
      price.metadata = metadata
      price.active = true
      price.stripe_id = stripe_price_id(price, product, unit_amount, interval, metadata)
      price.save!
      price
    end

    def stripe_product_id(product, name, kind, description)
      return product.stripe_id if real_stripe_id?(product.stripe_id)
      return "prod_local_#{name.parameterize.underscore}" if RecordingStudioStripe.configuration.local_mode?

      existing = find_stripe_demo_product(name)
      return existing.id if existing

      Client.current.v1.products.create(
        {
          name: name,
          description: description,
          metadata: { kind: kind, DEMO_METADATA_KEY => demo_key(name) }
        }
      ).id
    end

    def stripe_price_id(price, product, unit_amount, interval, metadata)
      return price.stripe_id if real_stripe_id?(price.stripe_id)
      if RecordingStudioStripe.configuration.local_mode?
        return "price_local_#{product.name.parameterize.underscore}_#{interval || 'once'}_#{unit_amount}"
      end

      existing = find_stripe_demo_price(product, unit_amount, interval)
      return existing.id if existing

      params = {
        product: product.stripe_id,
        unit_amount: unit_amount,
        currency: "usd",
        metadata: metadata.merge(DEMO_METADATA_KEY => demo_key(product.name))
      }
      params[:recurring] = { interval: interval } if interval.present?
      Client.current.v1.prices.create(params).id
    end

    def find_stripe_demo_product(name)
      key = demo_key(name)
      stripe_list_data(Client.current.v1.products.list(limit: 100)).find do |stripe_product|
        metadata_value(stripe_product, DEMO_METADATA_KEY) == key
      end
    end

    def find_stripe_demo_price(product, unit_amount, interval)
      stripe_list_data(Client.current.v1.prices.list(product: product.stripe_id, limit: 100)).find do |stripe_price|
        stripe_price.unit_amount.to_i == unit_amount.to_i && stripe_interval(stripe_price) == interval
      end
    end

    def real_stripe_id?(id)
      id.present? && !id.start_with?("prod_local_", "price_local_", "cus_local_", "sub_local_")
    end

    def demo_key(name)
      name.parameterize
    end

    def stripe_list_data(list)
      return [] if list.blank?
      return Array(list.data) if list.respond_to?(:data)

      Array(list)
    end

    def metadata_value(object, key)
      metadata = object.respond_to?(:metadata) ? object.metadata : nil
      return if metadata.blank?
      return metadata[key] || metadata[key.to_s] || metadata[key.to_sym] if metadata.respond_to?(:[])

      metadata.public_send(key) if metadata.respond_to?(key)
    end

    def stripe_interval(price)
      recurring = price.respond_to?(:recurring) ? price.recurring : nil
      interval = interval_from(recurring)
      return interval if interval.present? || recurring.present?
      return price.interval if price.respond_to?(:interval)

      nil
    end

    def interval_from(recurring)
      return if recurring.blank?
      return recurring[:interval] || recurring["interval"] if recurring.respond_to?(:[])

      recurring.interval if recurring.respond_to?(:interval)
    end
  end
end
