# frozen_string_literal: true

admin_root_recording = lambda do |**|
  admin_root = AdminRoot.find_by(name: "Studio Admin")
  next unless admin_root

  RecordingStudio.root_recording_for(admin_root)
end

RecordingStudioAccessible.configure do |config|
  config.admin_root_resolver = admin_root_recording
end

RecordingStudioAdmin.configure do |config|
  config.authentication_method = :authenticate_user!
  config.current_actor_method = :current_user
  config.access_recording_resolver = lambda do |context|
    RecordingStudioAccessible.admin_root(context: context)
  end
end

Rails.application.config.to_prepare do
  RecordingStudioAdmin::ApplicationController.helper ApplicationHelper
end
