# frozen_string_literal: true

module RecordingStudioStripe
  module Api
    module Authorize
      module_function

      def call(context, role)
        context.access_grant.authorize!(recording: context.root_recording, role: role)
      end
    end
  end
end
