# frozen_string_literal: true

module RecordingStudioStripe
  class PlansController < ApplicationController
    before_action :authorize_view!

    def index
      intervals = RecordingStudioStripe::PlanIntervals.from(params)
      @groups = Catalog.plan_groups.map do |group|
        key = group[:key]
        group.merge(
          subscription: billing.line(key).subscription,
          **intervals.hrefs_for(key) { |query| url_for(**query) }
        )
      end
    end
  end
end
