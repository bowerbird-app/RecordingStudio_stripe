class PressKitsController < ApplicationController
  def create
    recording = current_root_recording.record(PressKit) do |kit|
      kit.name = params.require(:name)
    end
    redirect_to root_path, notice: "#{recording.recordable.name} is in."
  rescue ActionController::ParameterMissing
    redirect_to root_path, alert: "Give it a name first."
  end
end
