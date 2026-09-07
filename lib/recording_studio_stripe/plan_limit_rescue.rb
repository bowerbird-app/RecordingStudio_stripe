# frozen_string_literal: true

module RecordingStudioStripe
  module PlanLimitRescue
    extend ActiveSupport::Concern

    included do
      rescue_from RecordingStudioStripe::PlanLimitReached, with: :recording_studio_stripe_plan_limit_reached
      rescue_from RecordingStudioStripe::MeterLimitReached, with: :recording_studio_stripe_meter_limit_reached
    end

    private

    def recording_studio_stripe_plan_limit_reached(error)
      if request.format.json?
        render json: { code: "plan_limit_reached", message: error.user_message }, status: :forbidden
      else
        redirect_to recording_studio_stripe_plans_url, alert: error.user_message
      end
    end

    def recording_studio_stripe_meter_limit_reached(error)
      if request.format.json?
        render json: { code: "meter_limit_reached", message: error.user_message }, status: :forbidden
      else
        redirect_to recording_studio_stripe_billing_url, alert: error.user_message
      end
    end

    def recording_studio_stripe_plans_url
      configured = RecordingStudioStripe.configuration.limit_reached_path
      return configured if configured.present?

      if respond_to?(:main_app, true) && main_app.respond_to?(:plans_path)
        main_app.plans_path
      elsif respond_to?(:plans_path)
        plans_path
      else
        RecordingStudioStripe.configuration.cancel_path
      end
    end

    def recording_studio_stripe_billing_url
      RecordingStudioStripe.configuration.success_path.presence ||
        RecordingStudioStripe.configuration.mount_path
    end
  end
end
