# frozen_string_literal: true

module RecordingStudioStripe
  module Api
    module Registration
      CHECKOUT_FIELDS = {
        price_id: { type: :string, required: true, allow_blank: false, description: "Price to start checkout with." },
        success_url: { type: :string, required: true, allow_blank: false, description: "Browser return after pay." },
        cancel_url: { type: :string, required: true, allow_blank: false, description: "Browser return if they stop." }
      }.freeze

      CHANGE_PLAN_FIELDS = {
        price_id: { type: :string, required: true, allow_blank: false, description: "Price to move the live plan to." }
      }.freeze

      SUBSCRIPTION_TYPE_FIELDS = {
        subscription_type: {
          type: :string,
          required: false,
          description: "Plan group when the workspace has more than one."
        }
      }.freeze

      PORTAL_FIELDS = {
        return_url: { type: :string, required: true, allow_blank: false, description: "Browser return from Stripe." }
      }.freeze

      ENDPOINTS = [
        {
          name: :show_billing,
          http_verb: :get,
          path: "billing",
          handler: Handlers::ShowBilling,
          role: :view,
          title: "Billing - Show",
          summary: "Billing - Show",
          tag: "Billing"
        },
        {
          name: :list_plans,
          http_verb: :get,
          path: "billing/plans",
          handler: Handlers::ListPlans,
          role: :view,
          title: "Plans - List",
          summary: "Plans - List",
          tag: "Plans"
        },
        {
          name: :start_checkout,
          http_verb: :post,
          path: "billing/checkout",
          handler: Handlers::StartCheckout,
          role: :admin,
          title: "Checkout - Start",
          summary: "Checkout - Start",
          tag: "Checkout",
          input_contract: { reject_unknown: true, fields: CHECKOUT_FIELDS }
        },
        {
          name: :change_plan,
          http_verb: :post,
          path: "billing/change_plan",
          handler: Handlers::ChangePlan,
          role: :admin,
          title: "Subscription - Change plan",
          summary: "Subscription - Change plan",
          tag: "Subscription",
          input_contract: { reject_unknown: true, fields: CHANGE_PLAN_FIELDS }
        },
        {
          name: :cancel_subscription,
          http_verb: :post,
          path: "billing/cancel",
          handler: Handlers::CancelSubscription,
          role: :admin,
          title: "Subscription - Cancel",
          summary: "Subscription - Cancel",
          tag: "Subscription",
          input_contract: { reject_unknown: true, fields: SUBSCRIPTION_TYPE_FIELDS }
        },
        {
          name: :resume_subscription,
          http_verb: :post,
          path: "billing/resume",
          handler: Handlers::ResumeSubscription,
          role: :admin,
          title: "Subscription - Resume",
          summary: "Subscription - Resume",
          tag: "Subscription",
          input_contract: { reject_unknown: true, fields: SUBSCRIPTION_TYPE_FIELDS }
        },
        {
          name: :keep_plan,
          http_verb: :post,
          path: "billing/keep_plan",
          handler: Handlers::KeepPlan,
          role: :admin,
          title: "Subscription - Keep plan",
          summary: "Subscription - Keep plan",
          tag: "Subscription",
          input_contract: { reject_unknown: true, fields: SUBSCRIPTION_TYPE_FIELDS }
        },
        {
          name: :start_portal,
          http_verb: :post,
          path: "billing/portal",
          handler: Handlers::StartPortal,
          role: :admin,
          title: "Portal - Start",
          summary: "Portal - Start",
          tag: "Portal",
          input_contract: { reject_unknown: true, fields: PORTAL_FIELDS }
        }
      ].freeze

      module_function

      def register!
        ENDPOINTS.each { |endpoint| register_one!(endpoint) }
      end

      def register_one!(endpoint)
        name = endpoint.fetch(:name)
        return if RecordingStudioApi.registered_endpoint(name)

        RecordingStudioApi.register_endpoint(
          name,
          http_verb: endpoint.fetch(:http_verb),
          path: endpoint.fetch(:path),
          handler: endpoint.fetch(:handler),
          openapi: {
            title: endpoint.fetch(:title),
            summary: endpoint.fetch(:summary),
            tags: [endpoint.fetch(:tag)]
          },
          input_contract: endpoint[:input_contract]
        )
      end
    end
  end
end
