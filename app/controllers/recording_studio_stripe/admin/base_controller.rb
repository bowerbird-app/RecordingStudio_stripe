# frozen_string_literal: true

module RecordingStudioStripe
  module Admin
    class BaseController < ::ApplicationController
      include RecordingStudio::UsesDefaultLayout

      layout "recording_studio/default_layout"

      before_action :require_admin_access!

      helper_method :admin_screen_url

      AdminContext = Struct.new(:controller) do
        def access_recording
          controller.send(:default_stripe_admin_recording)
        end

        def current_actor
          controller.send(:current_admin_actor)
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
          actor: current_admin_actor,
          recording: recording,
          role: :edit
        )
      end

      def admin_access_recording
        return unless defined?(RecordingStudioAdmin)

        resolver = RecordingStudioAdmin.configuration.site_admin_recording_resolver
        resolver&.call(AdminContext.new(self))
      end

      def current_admin_actor
        method_name = if defined?(RecordingStudioAdmin)
                        RecordingStudioAdmin.configuration.try(:current_actor_method).presence
                      end
        method_name ||= :current_user
        public_send(method_name) if respond_to?(method_name, true)
      end

      def default_stripe_admin_recording
        return unless defined?(RecordingStudio)

        types = RecordingStudio.configuration.try(:recordable_types)
        Array(types).each do |name|
          klass = name.to_s.safe_constantize
          next unless klass
          next unless RecordingStudio.capability_enabled?(:stripe_admin, for: klass)

          recordable = klass.first
          next unless recordable

          return RecordingStudio.root_recording_for(recordable)
        end
        nil
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
