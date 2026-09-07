# frozen_string_literal: true

module RecordingStudioStripe
  class ApplicationController < ::ApplicationController
    include RecordingStudio::UsesDefaultLayout

    layout "recording_studio/default_layout"

    before_action :require_root_recording!

    private

    def current_actor
      resolver = RecordingStudioStripe.configuration.current_actor
      return instance_exec(&resolver) if resolver
      return current_user if respond_to?(:current_user)

      Current.actor if defined?(Current)
    end

    def current_billing_root
      resolver = RecordingStudioStripe.configuration.current_root_recording
      return instance_exec(&resolver) if resolver
      return current_root_recording if defined?(current_root_recording)

      nil
    end

    def require_root_recording!
      unless current_actor
        redirect_to recording_studio_stripe_sign_in_url, alert: "Sign in to pick a plan."
        return
      end
      return if current_billing_root

      render plain: "Pick a workspace first.", status: :not_found
    end

    def billing
      @billing ||= RecordingStudioStripe::Billing.new(root_recording: current_billing_root)
    end
    helper_method :billing

    def authorize_view!
      authorize_role!(:view)
    end

    def authorize_edit!
      authorize_role!(:edit)
    end

    def authorize_admin!
      authorize_role!(:admin)
    end

    def authorize_role!(role)
      if defined?(RecordingStudioAccessible)
        return if RecordingStudioAccessible.authorized?(
          actor: current_actor,
          recording: current_billing_root,
          role: role
        )

        render plain: "You don’t have access to billing for this workspace.", status: :forbidden
        return
      end

      authenticator = RecordingStudioStripe.configuration.authenticate
      if authenticator
        return if instance_exec(&authenticator)

        render plain: "You don’t have access to billing for this workspace.", status: :forbidden
        return
      end

      render plain: "You don’t have access to billing for this workspace.", status: :forbidden
    end

    def after_checkout_url
      "#{request.base_url}#{RecordingStudioStripe.configuration.success_path}"
    end

    def checkout_cancel_url
      "#{request.base_url}#{RecordingStudioStripe.configuration.cancel_path}"
    end

    def recording_studio_stripe_sign_in_url
      if respond_to?(:main_app, true) && main_app.respond_to?(:new_user_session_path)
        main_app.new_user_session_path
      else
        "/"
      end
    end
  end
end
