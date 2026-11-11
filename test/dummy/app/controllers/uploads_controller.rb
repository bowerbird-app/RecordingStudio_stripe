# frozen_string_literal: true

class UploadsController < ApplicationController
  def create
    byte_size = Integer(params.require(:byte_size))
    current_root_recording.recordable.billing.limit(:max_file_bytes).enforce_item!(byte_size)
    redirect_to root_path, notice: "That file fits."
  end
end
