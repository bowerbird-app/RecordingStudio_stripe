# frozen_string_literal: true

module RecordingStudioStripe
  module Api
    module Handlers
      module_function

      def invalid!(error)
        raise RecordingStudioApi::InvalidActionInputError, error.message
      end

      def saleable_price(id)
        Price.active.includes(:product).find_by(id: id)
      end

      class ShowBilling
        def self.call(context)
          Authorize.call(context, :view)
          Serialize.billing(Billing.for(context.root_recording.recordable))
        end
      end

      class ListPlans
        def self.call(context)
          Authorize.call(context, :view)
          Serialize.plan_groups(Catalog.plan_groups)
        end
      end

      class StartCheckout
        def self.call(context)
          Authorize.call(context, :admin)
          price = Handlers.saleable_price(context.params[:price_id])
          raise RecordingStudioApi::InvalidActionInputError, Copy.t("alerts.pick_plan") unless price

          result = RecordingStudioStripe::StartCheckout.call(
            root_recording: context.root_recording,
            price: price,
            actor: context.access_grant.actor,
            success_url: context.params[:success_url],
            cancel_url: context.params[:cancel_url]
          )
          Serialize.checkout(result)
        rescue InvalidPrice => e
          Handlers.invalid!(e)
        end
      end

      class ChangePlan
        def self.call(context)
          Authorize.call(context, :admin)
          price = Handlers.saleable_price(context.params[:price_id])
          raise RecordingStudioApi::InvalidActionInputError, Copy.t("alerts.pick_plan") unless price

          Serialize.subscription(
            RecordingStudioStripe::ChangePlan.call(
              root_recording: context.root_recording,
              price: price,
              actor: context.access_grant.actor
            )
          )
        rescue InvalidPrice, NoSubscription => e
          Handlers.invalid!(e)
        end
      end

      class CancelSubscription
        def self.call(context)
          Authorize.call(context, :admin)
          Serialize.subscription(
            RecordingStudioStripe::CancelSubscription.call(
              root_recording: context.root_recording,
              subscription_type: context.params[:subscription_type]
            )
          )
        rescue NoSubscription => e
          Handlers.invalid!(e)
        end
      end

      class ResumeSubscription
        def self.call(context)
          Authorize.call(context, :admin)
          Serialize.subscription(
            RecordingStudioStripe::ResumeSubscription.call(
              root_recording: context.root_recording,
              subscription_type: context.params[:subscription_type]
            )
          )
        rescue NoSubscription => e
          Handlers.invalid!(e)
        end
      end

      class KeepPlan
        def self.call(context)
          Authorize.call(context, :admin)
          Serialize.subscription(
            RecordingStudioStripe::ClearScheduledChange.call(
              root_recording: context.root_recording,
              subscription_type: context.params[:subscription_type]
            )
          )
        rescue NoSubscription => e
          Handlers.invalid!(e)
        end
      end

      class StartPortal
        def self.call(context)
          Authorize.call(context, :admin)
          Serialize.portal(
            RecordingStudioStripe::StartPortalSession.call(
              root_recording: context.root_recording,
              return_url: context.params[:return_url]
            )
          )
        rescue NoCustomer
          raise RecordingStudioApi::InvalidActionInputError, Copy.t("alerts.portal_needs_pay")
        rescue Stripe::StripeError
          raise RecordingStudioApi::InvalidActionInputError, Copy.t("alerts.portal_failed")
        end
      end
    end
  end
end
