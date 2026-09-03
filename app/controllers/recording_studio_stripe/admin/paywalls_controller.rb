# frozen_string_literal: true

module RecordingStudioStripe
  module Admin
    class PaywallsController < BaseController
      def new; end

      def create
        paywall = Paywall.create!(
          name: params.require(:name).to_s.parameterize(separator: "_"),
          label: params.require(:label)
        )
        RegisterPaywallActions.call
        redirect_to admin_screen_url("paywalls"), notice: "#{paywall.label} is ready to tick on a plan."
      rescue ActiveRecord::RecordInvalid => e
        flash.now[:alert] = e.message
        render :new, status: :unprocessable_entity
      end
    end
  end
end
