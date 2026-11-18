# frozen_string_literal: true

module RecordingStudioStripe
  class PlansController < ApplicationController
    skip_before_action :authenticate_user!, if: :guest_plans?, raise: false
    before_action :authorize_view!, unless: :guest_plans?

    def index
      intervals = RecordingStudioStripe::PlanIntervals.from(params)
      @guest_plans = guest_plans?
      @signup_href = public_plans_signup_href if @guest_plans
      @groups = plan_groups(intervals)
    end

    private

    def require_root_recording!
      return if guest_plans?

      super
    end

    def plan_groups(intervals)
      Catalog.plan_groups.map { |group| present_group(group, intervals) }
    end

    def present_group(group, intervals)
      key = group[:key]
      fields = { **intervals.hrefs_for(key) { |query| url_for(**query) } }
      if guest_plans?
        fields[:products] = guest_products(group[:products])
        fields[:subscription] = nil
      else
        fields[:subscription] = billing.line(key).subscription
      end
      group.merge(fields)
    end

    def guest_products(products)
      Array(products).select { |product| product.plan? && product.active? && active_recurring_price?(product) }
    end

    def active_recurring_price?(product)
      product.prices.any? { |price| price.active? && price.recurring? }
    end

    def guest_plans?
      return @guest_plans if defined?(@guest_plans)

      @guest_plans = RecordingStudioStripe.configuration.public_plans &&
                     (current_actor.blank? || current_billing_root.blank?)
    end

    def public_plans_signup_href
      setting = RecordingStudioStripe.configuration.public_plans_signup_path
      return if setting.blank?

      value = setting.respond_to?(:call) ? instance_exec(&setting) : setting
      value.to_s.presence
    end
  end
end
