# frozen_string_literal: true

module RecordingStudioStripe
  class SeedDemoCatalog
    def self.call
      new.call
    end

    def call
      Meter.sync_from_config!
      Paywall.sync_from_config!
      studio_type = typed?("studio") ? "studio" : SubscriptionTypes.keys.first
      starter = upsert_product("Starter", "plan", "A quiet start.", studio_type)
      pro = upsert_product("Pro", "plan", "The usual working plan.", studio_type)
      team = upsert_product("Team", "plan", "Room for the crew.", studio_type)
      tokens = upsert_product("AI token packs", "allowance", "Extra AI tokens for this period.")
      pro.assign_paywalls(%w[generate_image])
      team.assign_paywalls(%w[generate_image])
      if Limits.known?("press_kits")
        starter.assign_limits("press_kits" => 3)
        starter.save!
        pro.assign_limits("press_kits" => 10)
        pro.save!
        team.assign_limits("press_kits" => 25)
        team.save!
      end
      seed_inbox_plans if typed?("inbox")
      RegisterPaywallActions.call

      upsert_price(starter, 900, "month", { "included_ai_tokens" => "1000000", "included_api_calls" => "10000" })
      upsert_price(starter, 9000, "year", { "included_ai_tokens" => "1000000", "included_api_calls" => "10000" })
      upsert_price(pro, 2900, "month", { "included_ai_tokens" => "10000000", "included_api_calls" => "100000" })
      upsert_price(pro, 29_000, "year", { "included_ai_tokens" => "10000000", "included_api_calls" => "100000" })
      upsert_price(team, 7900, "month", { "included_ai_tokens" => "50000000", "included_api_calls" => "500000" })
      upsert_price(team, 79_000, "year", { "included_ai_tokens" => "50000000", "included_api_calls" => "500000" })
      upsert_price(tokens, 1000, nil, { "meter" => "ai_tokens", "allowance" => "5000000" })
      upsert_price(tokens, 3000, nil, { "meter" => "ai_tokens", "allowance" => "20000000" })
    end

    private

    def seed_inbox_plans
      inbox = upsert_product("Inbox", "plan", "Keep an eye on what people send.", "inbox")
      inbox_plus = upsert_product("Inbox Plus", "plan", "More room in the inbox.", "inbox")
      inbox_pro = upsert_product("Inbox Pro", "plan", "The inbox that can take it.", "inbox")
      inbox_plus.assign_paywalls(%w[export_csv])
      inbox_pro.assign_paywalls(%w[export_csv])
      upsert_price(inbox, 2500, "month", { "included_api_calls" => "5000" })
      upsert_price(inbox, 25_000, "year", { "included_api_calls" => "5000" })
      upsert_price(inbox_plus, 5000, "month", { "included_api_calls" => "50000" })
      upsert_price(inbox_plus, 50_000, "year", { "included_api_calls" => "50000" })
      upsert_price(inbox_pro, 9000, "month", { "included_api_calls" => "200000" })
      upsert_price(inbox_pro, 90_000, "year", { "included_api_calls" => "200000" })
    end

    def typed?(key)
      SubscriptionTypes.known?(key) && SubscriptionTypes.configured?
    end

    def upsert_product(name, kind, description, subscription_type = nil)
      product = Product.find_or_initialize_by(name: name, kind: kind)
      type = SubscriptionTypes.normalize(subscription_type)
      product.stripe_id ||= "prod_local_#{name.parameterize.underscore}"
      product.description = description
      product.active = true
      product.subscription_type = type
      product.metadata = { "kind" => kind, "subscription_type" => type }
      product.save!
      product
    end

    def upsert_price(product, unit_amount, interval, metadata)
      price = product.prices.find_or_initialize_by(unit_amount: unit_amount, interval: interval)
      price.stripe_id ||= "price_local_#{product.name.parameterize.underscore}_#{interval || 'once'}_#{unit_amount}"
      price.currency = "usd"
      price.metadata = metadata
      price.active = true
      price.save!
      price
    end
  end
end
