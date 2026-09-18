# frozen_string_literal: true

module RecordingStudioStripe
  class CreateProduct
    def self.call(name:, kind:, description: nil, active: true, paywall_names: [], subscription_type: nil, limits: {},
                  plan_card: nil, trial_days: nil, trial_unit_amount: nil)
      new(
        name: name,
        kind: kind,
        description: description,
        active: active,
        paywall_names: paywall_names,
        subscription_type: subscription_type,
        limits: limits,
        plan_card: plan_card,
        trial_days: trial_days,
        trial_unit_amount: trial_unit_amount
      ).call
    end

    def initialize(name:, kind:, description:, active:, paywall_names:, subscription_type:, limits:, plan_card:,
                   trial_days:, trial_unit_amount:)
      @name = name
      @kind = kind
      @description = description
      @active = active
      @paywall_names = paywall_names
      @subscription_type = subscription_type
      @limits = limits
      @plan_card = plan_card
      @trial_days = trial_days
      @trial_unit_amount = trial_unit_amount
    end

    def call
      raise InvalidPrice, "Kind must be plan or allowance" unless Product::KINDS.include?(@kind)

      type = SubscriptionTypes.normalize(@subscription_type)
      raise InvalidPrice, "Unknown plan group" if @kind == "plan" && !SubscriptionTypes.known?(type)

      stripe_id = create_stripe_id(type)
      product = Product.new(
        stripe_id: stripe_id,
        name: @name,
        description: @description,
        kind: @kind,
        active: @active,
        subscription_type: type,
        metadata: { "kind" => @kind, "subscription_type" => type }
      )
      product.assign_limits(@limits)
      product.assign_plan_card(@plan_card)
      product.save!
      product.assign_paywalls(@paywall_names)
      assign_trial(product)
      product
    end

    private

    def assign_trial(product)
      return unless product.plan?
      return if @trial_days.nil? && @trial_unit_amount.nil?

      AssignTrial.call(product: product, days: @trial_days, unit_amount: @trial_unit_amount)
    end

    def create_stripe_id(type)
      return "prod_local_#{SecureRandom.hex(6)}" if RecordingStudioStripe.configuration.local_mode?

      result = Client.current.v1.products.create(
        {
          name: @name,
          description: @description,
          metadata: stripe_metadata(type)
        }
      )
      result.id
    end

    def stripe_metadata(type)
      data = { kind: @kind, subscription_type: type }
      return data if @kind != "plan"

      @limits.to_h.stringify_keys.each do |name, value|
        next if value.blank? || !Limits.known?(name)
        next unless Limits.fetch(name).subscription_type == type

        data["limit_#{name}"] = value.to_i.to_s
      end
      merge_trial_metadata(data)
      data
    end

    def merge_trial_metadata(data)
      days = Integer(@trial_days, exception: false).to_i
      return unless days.positive?

      data["trial_days"] = days.to_s
      data["trial_unit_amount"] = Integer(@trial_unit_amount, exception: false).to_i.to_s
    end
  end
end
