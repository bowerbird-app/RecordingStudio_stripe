# frozen_string_literal: true

module RecordingStudioStripe
  module Admin
    # Catalogue screens stay on Accessible :view. Writes on the product and
    # price forms need :admin on the site-admin root. :edit includes :view
    # and does not include :admin.
    module CatalogueAccess
      module_function

      def role_for(request)
        return :admin unless request
        return :view if request.get? || request.head?

        :admin
      end

      def allowed?(actor:, controller:, role:)
        recording = RecordingStudioStripe.site_admin_recording_for(controller)
        return false unless recording
        return false unless RecordingStudioStripe.accessible_loaded?
        return false unless actor

        RecordingStudioAccessible.authorized?(
          actor: actor,
          recording: recording,
          role: role
        )
      end

      def write_allowed?(context)
        allowed?(
          actor: context.current_actor,
          controller: context.controller,
          role: :admin
        )
      end
    end
  end
end
