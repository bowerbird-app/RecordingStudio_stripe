# frozen_string_literal: true

module RecordingStudioStripe
  module SiteAdminRecording
    module_function

    def for(controller = nil)
      value = value_from_setting(controller)
      return if value.nil?

      recording = recording_from(value)
      return unless stripe_admin?(recording)

      recording
    end

    def value_from_setting(controller)
      setting = RecordingStudioStripe.configuration.site_admin_recording
      return if setting.nil?
      return setting unless setting.respond_to?(:call)

      call_setting(setting, controller)
    end

    def call_setting(setting, controller)
      parameter = setting.parameters.find { |kind, _name| ARGUMENT_KINDS.include?(kind) }
      return invoke_without_argument(setting, controller) unless parameter

      kind = parameter.first
      return setting.call(controller: controller) if %i[key keyreq].include?(kind)

      setting.call(controller)
    end

    def invoke_without_argument(setting, controller)
      return setting.call unless controller

      controller.instance_exec(&setting)
    end

    def recording_from(value)
      return unless defined?(RecordingStudio)
      return value if defined?(RecordingStudio::Recording) && value.is_a?(RecordingStudio::Recording)

      RecordingStudio.root_recording_for(value)
    end

    def stripe_admin?(recording)
      recordable = recording&.recordable
      return false unless recordable

      RecordingStudio.capability_enabled?(:stripe_admin, for: recordable.class)
    end

    ARGUMENT_KINDS = %i[req opt key keyreq].freeze
    private_constant :ARGUMENT_KINDS
  end
end
