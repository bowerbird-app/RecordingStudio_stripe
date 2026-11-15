# frozen_string_literal: true

module RecordingStudioStripe
  module AdminSupport
    extend ActiveSupport::Concern

    def self.default_site_admin_recording_for(context)
      controller = context.respond_to?(:controller) ? context.controller : nil
      named = RecordingStudioStripe.site_admin_recording_for(controller)
      return named if named

      fallback = context.respond_to?(:access_recording) ? context.access_recording : nil
      fallback if SiteAdminRecording.stripe_admin?(fallback)
    end

    included do |base|
      unless defined?(RecordingStudioAdmin::AllowsAdminSections)
        raise LoadError, "recording_studio_admin is required to enable Stripe admin sections"
      end

      base.include RecordingStudioAdmin::AllowsAdminSections
      RecordingStudioStripe.register_capabilities!
      RecordingStudio.enable_capability(:stripe_admin, on: base)

      if defined?(RecordingStudioAccessible)
        RecordingStudioAccessible.configuration.admin_root_resolver ||= lambda do |context: nil|
          RecordingStudioStripe::AdminSupport.default_site_admin_recording_for(context)
        end
      end

      base.recording_studio_admin_sections do
        section :stripe
      end
    end
  end
end
