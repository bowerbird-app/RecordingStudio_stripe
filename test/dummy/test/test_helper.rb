# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"
require "rails/test_help"

module StripeBillingTestHelpers
  def grant_owner_access!(recording:, actor:, role: :admin)
    return if RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: role)

    RecordingStudioAccessible::AccessCreationContext.allow do
      RecordingStudio.root_recording_or_self(recording).record(
        RecordingStudio::Access,
        parent_recording: recording
      ) do |access|
        access.actor = actor
        access.role = role
      end
    end
  end
end

ActiveSupport::TestCase.include StripeBillingTestHelpers

class ActionDispatch::IntegrationTest
  include StripeBillingTestHelpers

  MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"

  %i[get post patch put delete head].each do |http_method|
    define_method(http_method) do |path, **args|
      headers = args.fetch(:headers, {}).dup
      headers["User-Agent"] ||= MODERN_USER_AGENT
      super(path, **args.merge(headers: headers))
    end
  end
end
