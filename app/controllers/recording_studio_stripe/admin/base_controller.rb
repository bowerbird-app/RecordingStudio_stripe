# frozen_string_literal: true

module RecordingStudioStripe
  module Admin
    class BaseController < ::ApplicationController
      include RecordingStudio::UsesDefaultLayout

      layout "recording_studio/default_layout"

      before_action :require_admin_access!

      AdminContext = Struct.new(:controller) do
        def access_recording
          nil
        end
      end

      private

      def require_admin_access!
        return if admin_authorized?

        render plain: "Staff only.", status: :forbidden
      end

      def admin_authorized?
        recording = admin_access_recording
        return false unless recording
        return true unless defined?(RecordingStudioAccessible)

        RecordingStudioAccessible.authorized?(
          actor: current_user,
          recording: recording,
          role: :edit
        )
      end

      def admin_access_recording
        return unless defined?(RecordingStudioAdmin)

        resolver = RecordingStudioAdmin.configuration.site_admin_recording_resolver
        resolver&.call(AdminContext.new(self))
      end

      def admin_screen_url(key)
        "/admin/screens/#{key}"
      end
    end
  end
end
