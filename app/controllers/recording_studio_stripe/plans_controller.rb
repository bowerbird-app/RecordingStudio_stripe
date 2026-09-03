# frozen_string_literal: true

module RecordingStudioStripe
  class PlansController < ApplicationController
    before_action :authorize_view!

    def index
      @interval = params[:interval].presence_in(%w[month year]) || "month"
      @groups = Catalog.plan_groups.map do |group|
        group.merge(subscription: billing.line(group[:key]).subscription)
      end
    end
  end
end
