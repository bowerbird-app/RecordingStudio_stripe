# frozen_string_literal: true

class PricingController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    intervals = RecordingStudioStripe::PlanIntervals.from(params)
    @groups = RecordingStudioStripe::Catalog.plan_groups.map do |group|
      key = group[:key]
      group.merge(intervals.hrefs_for(key) { |query| pricing_path(**query) })
    end
  end

  private

  def application_layout
    "public"
  end
end
