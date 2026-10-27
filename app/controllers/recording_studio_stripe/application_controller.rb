# frozen_string_literal: true

module RecordingStudioStripe
  class ApplicationController < ::ApplicationController
    # CSRF must run before host auth and ControllerAuth filters. Use prepend
    # so a local protect_from_forgery does not fall behind authenticate_user!.
    protect_from_forgery with: :exception, prepend: true

    include RecordingStudioAccessible::ControllerAuth

    recording_studio_layout { RecordingStudioStripe.configuration.layout }

    recording_studio_auth(
      config: -> { RecordingStudioStripe.configuration },
      prefix: :stripe,
      authenticate: false,
      set_current_actor: false,
      require_actor: true,
      actor_method: :current_actor,
      root_method: :current_billing_root,
      actor_resolver: lambda {
        resolver = RecordingStudioStripe.configuration.current_actor
        next instance_exec(&resolver) if resolver
        next current_user if respond_to?(:current_user)

        Current.actor if defined?(Current)
      },
      root_resolver: lambda {
        resolver = RecordingStudioStripe.configuration.current_root_recording
        next instance_exec(&resolver) if resolver
        next current_root_recording if defined?(current_root_recording)

        nil
      },
      on_missing_actor_for_root: lambda {
        redirect_to recording_studio_stripe_sign_in_url, alert: Copy.t("alerts.sign_in")
      },
      missing_root_status: :not_found,
      missing_actor_status: :forbidden,
      response_style: lambda { |status, reason|
        body =
          case reason
          when :missing_root then Copy.t("alerts.pick_workspace")
          when :forbidden, :missing_actor then Copy.t("alerts.no_access")
          else
            status.to_s.tr("_", " ")
          end
        render plain: body, status: status
      }
    )

    # ControllerAuth exposes the root method as a helper; main did not.
    self._helper_methods = _helper_methods - [:current_billing_root]
    _helpers_for_modification.class_eval do
      undef_method :current_billing_root if method_defined?(:current_billing_root)
    end

    before_action :require_root_recording!

    private

    def require_root_recording!
      require_root!
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

    # Same as main: Accessible when loaded; otherwise config.authenticate; else fail closed.
    # ControllerAuth has no authenticate fallback, so this stays on the gem.
    def authorize_role!(role)
      if defined?(RecordingStudioAccessible)
        return if RecordingStudioAccessible.authorized?(
          actor: current_actor,
          recording: current_billing_root,
          role: role
        )

        render plain: Copy.t("alerts.no_access"), status: :forbidden
        return
      end

      authenticator = RecordingStudioStripe.configuration.authenticate
      if authenticator
        return if instance_exec(&authenticator)

        render plain: Copy.t("alerts.no_access"), status: :forbidden
        return
      end

      render plain: Copy.t("alerts.no_access"), status: :forbidden
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
