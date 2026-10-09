# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"
require "rails/test_help"

module StripeBillingTestHelpers
  def grant_owner_access!(recording:, actor:, role: :admin, manager_actor: nil)
    return if RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: role)

    if role.to_s == "admin"
      result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: actor)
      return if result.success?
    end

    manager = manager_actor || admin_actor_for(recording) || actor
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role,
      manager_actor: manager
    )
    raise(result.error || "Failed to grant #{role} access") if result.failure?
  end

  def admin_actor_for(recording)
    target = RecordingStudio.root_recording_or_self(recording)
    RecordingStudio::Recording.unscoped
      .where(recordable_type: "RecordingStudio::Access", trashed_at: nil)
      .where(root_recording_id: target.id)
      .find_each do |access_recording|
        access = access_recording.recordable
        next unless access&.role.to_s == "admin"

        return access.actor
      end
    nil
  end
end

ActiveSupport::TestCase.include StripeBillingTestHelpers

RecordingStudioStripe.configuration.secret_key = nil
RecordingStudioStripe.configuration.publishable_key = nil
RecordingStudioStripe.configuration.webhook_secret = nil
RecordingStudioStripe.configuration.client = nil

class ActionDispatch::IntegrationTest
  include StripeBillingTestHelpers

  MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"

  def switch_to_root!(recording)
    patch "/recording_studio_root_switchable/v1/root_switch", params: {
      scope: "all_workspaces",
      root_switch: {
        root_recording_id: recording.id,
        return_to: "/"
      }
    }
    follow_redirect! if response.redirect?
    get "/up"
  end

  %i[get post patch put delete head].each do |http_method|
    define_method(http_method) do |path, **args|
      headers = args.fetch(:headers, {}).dup
      headers["User-Agent"] ||= MODERN_USER_AGENT
      super(path, **args.merge(headers: headers))
    end
  end
end
