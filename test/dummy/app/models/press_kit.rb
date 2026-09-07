class PressKit < ApplicationRecord
  recording_studio_recordable label: "Press kit", root: false, allowed_parent_types: ["Workspace", "Folder"]
end
