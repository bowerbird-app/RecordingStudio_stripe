# frozen_string_literal: true

RecordingStudioRootSwitchable.configure do |config|
  config.current_actor_resolver = lambda do |controller:|
    Current.actor || controller.current_user
  end

  config.after_switch_redirect = lambda do |controller:, return_to:, **|
    candidate_path = return_to.presence
    candidate_path = controller.main_app.root_path if candidate_path.blank?

    if internal_route?(candidate_path)
      candidate_path
    else
      controller.main_app.root_path
    end
  end

  config.scope :all_workspaces do |scope|
    scope.label = "All roots"
    scope.description = "Workspaces plus Studio Admin."
    # Root Switchable 0.15 requires Accessible :view on the current root.
    # Listing a root the actor cannot view makes that root current and the switch page answers 403.
    scope.available_roots = lambda do |actor: nil, **|
      next [] if actor.blank?

      workspace_roots = Workspace.order(:name).filter_map do |workspace|
        RecordingStudio.root_recording_for(workspace)
      end
      admin_roots = AdminRoot.order(:name).filter_map do |admin_root|
        RecordingStudio.root_recording_for(admin_root)
      end
      (workspace_roots + admin_roots).select do |recording|
        actor_can_view_root?(actor, recording)
      end
    end
    scope.access_check = lambda do |actor: nil, recording: nil, **|
      actor_can_view_root?(actor, recording)
    end

    scope.default_root = lambda do |roots:, **|
      roots.first
    end
  end
end

def actor_can_view_root?(actor, recording)
  return false if actor.blank? || recording.blank?
  return true unless defined?(::RecordingStudioAccessible)

  RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: :view)
end

def internal_route?(path)
  routes = [
    Rails.application.routes,
    RecordingStudioRootSwitchable::Engine.routes
  ]

  routes.any? do |route_set|
    route_set.recognize_path(path, method: :get)
    true
  rescue StandardError
    false
  end
end
