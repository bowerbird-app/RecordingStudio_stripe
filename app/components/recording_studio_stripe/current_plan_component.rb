# frozen_string_literal: true

module RecordingStudioStripe
  class CurrentPlanComponent < ViewComponent::Base
    def initialize(subscription:, can_manage: true)
      super()
      @subscription = subscription
      @can_manage = can_manage
    end

    def call
      pieces = [notices, plan_summary].compact
      return pieces.first if pieces.one?

      render FlatPack::Collection::Component.new(as: :list, layout: :stack, gap: :md) do |stack|
        pieces.each { |piece| stack.with_item { piece } }
      end
    end

    private

    def notices
      component = CurrentPlanNoticesComponent.new(subscription: @subscription)
      render(component) if component.render?
    end

    def plan_summary
      state = CurrentPlanState.new(@subscription)
      actions = CurrentPlanActionsComponent.new(subscription: @subscription, can_manage: @can_manage)

      render FlatPack::Billing::PlanSummary::Component.new(
        plan_name: state.plan_name,
        price_text: state.price_text,
        status: state.status,
        renews_on: state.renews_on,
        trial_ends_on: state.trial_ends_on,
        description: state.description
      ) do |summary|
        summary.actions { render(actions) }
      end
    end
  end
end
