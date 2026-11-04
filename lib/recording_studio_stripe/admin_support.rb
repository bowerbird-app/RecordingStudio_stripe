# frozen_string_literal: true

module RecordingStudioStripe
  module AdminSupport
    extend ActiveSupport::Concern

    def self.default_site_admin_recording_for(context)
      RecordingStudioStripe.site_admin_recording_for(context.controller) || context.access_recording
    end

    included do |base|
      unless defined?(RecordingStudioAdmin::AllowsAdminSections)
        raise LoadError, "recording_studio_admin is required to enable Stripe admin sections"
      end

      base.include RecordingStudioAdmin::AllowsAdminSections
      RecordingStudioStripe.register_capabilities!
      RecordingStudio.enable_capability(:stripe_admin, on: base)

      RecordingStudioAdmin.configuration.site_admin_recording_resolver ||= lambda do |context|
        RecordingStudioStripe::AdminSupport.default_site_admin_recording_for(context)
      end

      base.recording_studio_admin_sections do
        section :stripe
      end
    end
  end
end
