# frozen_string_literal: true

require_relative "api/authorize"
require_relative "api/serialize"
require_relative "api/handlers"
require_relative "api/registration"

module RecordingStudioStripe
  module Api
    def self.available?
      defined?(RecordingStudioApi) && RecordingStudioApi.respond_to?(:register_endpoint)
    end

    def self.register!
      return unless available?

      Registration.register!
      true
    end
  end
end
