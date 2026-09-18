# frozen_string_literal: true

module RecordingStudioStripe
  class UsageController < ApplicationController
    before_action :authorize_view!

    def show
      @lines = billing.active_lines
    end
  end
end
