class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", root: true
  include RecordingStudioStripe::Billable
  RecordingStudio.enable_capability(:api_access_point, on: self)
end
