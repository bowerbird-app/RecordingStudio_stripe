# frozen_string_literal: true

module RecordingStudioStripe
  module Admin
    class MetersController < BaseController
      def new; end

      def create
        meter = Meter.create!(
          name: params.require(:name).to_s.parameterize(separator: "_"),
          label: params.require(:label)
        )
        redirect_to admin_screen_url("meters"), notice: "#{meter.label} is ready to count."
      rescue ActiveRecord::RecordInvalid => e
        flash.now[:alert] = e.message
        render :new, status: :unprocessable_entity
      end
    end
  end
end
