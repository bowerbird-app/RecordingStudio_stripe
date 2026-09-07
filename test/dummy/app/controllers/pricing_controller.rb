# frozen_string_literal: true

class PricingController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    intervals = RecordingStudioStripe::PlanIntervals.from(params)
    billing = current_pricing_billing
    @groups = RecordingStudioStripe::Catalog.plan_groups.map do |group|
      key = group[:key]
      group.merge(
        subscription: billing&.line(key)&.subscription,
        **intervals.hrefs_for(key) { |query| pricing_path(**query) }
      )
    end
  end

  private

  def current_pricing_billing
    return unless user_signed_in?
    return unless current_root_recording

    RecordingStudioStripe::Billing.for_recording(current_root_recording)
  end

  def application_layout
    "public"
  end
end
