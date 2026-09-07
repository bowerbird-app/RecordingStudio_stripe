class PressKitsController < ApplicationController
  def index
    return if current_root_recording&.recordable.is_a?(Workspace)

    redirect_to root_path, alert: "Switch to a workspace to add press kits."
  end

  def create
    recording = current_root_recording.record(PressKit) do |kit|
      kit.name = params.require(:name)
    end
    redirect_to press_kits_path, notice: "#{recording.recordable.name} is in."
  rescue ActionController::ParameterMissing
    redirect_to press_kits_path, alert: "Give it a name first."
  end
end
