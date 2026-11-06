# frozen_string_literal: true

module RecordingStudioStripe
  module Admin
    class BaseController < ::ApplicationController
      recording_studio_layout { RecordingStudioStripe.configuration.layout }

      before_action :require_admin_access!

      helper_method :admin_screen_url

      private

      def require_admin_access!
        return if admin_authorized?

        render plain: Copy.t("admin.staff_only", default: "Staff only."), status: :forbidden
      end

      def admin_authorized?
        recording = admin_access_recording
        return false unless recording
        return false unless defined?(RecordingStudioAccessible)

        RecordingStudioAccessible.authorized?(
          actor: current_admin_actor,
          recording: recording,
          role: :edit
        )
      end

      def admin_access_recording
        RecordingStudioStripe.site_admin_recording_for(self)
      end

      def current_admin_actor
        method_name = if defined?(RecordingStudioAdmin)
                        RecordingStudioAdmin.configuration.try(:current_actor_method).presence
                      end
        method_name ||= :current_user
        public_send(method_name) if respond_to?(method_name, true)
      end

      def admin_screen_url(key)
        mount = if defined?(RecordingStudioAdmin) && RecordingStudioAdmin.configuration.respond_to?(:mount_path)
                  RecordingStudioAdmin.configuration.mount_path.presence
                end
        "#{mount.presence || '/admin'}/screens/#{key}"
      end
    end
  end
end
