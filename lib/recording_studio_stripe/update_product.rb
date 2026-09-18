# frozen_string_literal: true

module RecordingStudioStripe
  class UpdateProduct
    include StripeRequest

    def self.call(product:, name:, description: nil, paywall_names: [], subscription_type: nil, limits: nil,
                  plan_card: nil, trial_days: nil, trial_unit_amount: nil)
      new(
        product: product,
        name: name,
        description: description,
        paywall_names: paywall_names,
        subscription_type: subscription_type,
        limits: limits,
        plan_card: plan_card,
        trial_days: trial_days,
        trial_unit_amount: trial_unit_amount
      ).call
    end

    def initialize(product:, name:, description:, paywall_names:, subscription_type:, limits:, plan_card:,
                   trial_days:, trial_unit_amount:)
      @product = product
      @name = name
      @description = description
      @paywall_names = paywall_names
      @subscription_type = subscription_type
      @limits = limits
      @plan_card = plan_card
      @trial_days = trial_days
      @trial_unit_amount = trial_unit_amount
    end

    def call
      type = SubscriptionTypes.normalize(@subscription_type.presence || @product.subscription_type)
      @product.assign_attributes(name: @name, description: @description, subscription_type: type)
      @product.metadata = @product.metadata.merge("subscription_type" => type)
      @product.assign_limits(@limits)
      @product.assign_plan_card(@plan_card)
      assign_trial
      update_stripe(type)
      @product.save!
      @product.assign_paywalls(@paywall_names)
      @product
    end

    private

    def assign_trial
      return unless @product.plan?
      return if @trial_days.nil? && @trial_unit_amount.nil?

      AssignTrial.call(product: @product, days: @trial_days, unit_amount: @trial_unit_amount)
    end

    def update_stripe(type)
      return if RecordingStudioStripe.configuration.local_mode?

      stripe_product = Client.current.v1.products.retrieve(@product.stripe_id)
      existing = stringify_metadata(stripe_get(stripe_product, :metadata))
      Client.current.v1.products.update(
        @product.stripe_id,
        {
          name: @name,
          description: @description,
          metadata: stripe_metadata(type, existing)
        }
      )
    end

    def stripe_metadata(type, existing)
      data = existing.merge("kind" => @product.kind, "subscription_type" => type)
      Limits.all.each do |definition|
        quantity = @product.limit_quantity(definition.name)
        data["limit_#{definition.name}"] = quantity.positive? ? quantity.to_s : ""
      end
      merge_trial_metadata(data)
      data
    end

    def merge_trial_metadata(data)
      trial = Trial.for(@product)
      if trial.offered?
        data["trial_days"] = trial.days.to_s
        data["trial_unit_amount"] = trial.unit_amount.to_s
      else
        data["trial_days"] = ""
        data["trial_unit_amount"] = ""
      end
    end
  end
end
