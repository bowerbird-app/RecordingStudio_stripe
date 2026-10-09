# frozen_string_literal: true

require_relative "api/access"
require "recording_studio_metrics"

module RecordingStudioStripe
  module Metrics
    API = :operations
    EXPOSE = { api: [API] }.freeze
    AUTHORIZE = ->(context) { RecordingStudioStripe::Api::Access.can_view?(context) }

    module_function

    def register!
      register_subscriptions!
      register_usage!
    end

    def register_subscriptions!
      RecordingStudioMetrics.register(
        :stripe_subscriptions,
        model: RecordingStudioStripe::Subscription,
        blast_radius: :site,
        api_authorize: AUTHORIZE
      ) do
        RecordingStudioStripe::Metrics.define_subscriptions(self)
      end
    end

    def register_usage!
      RecordingStudioMetrics.register(
        :stripe_usage,
        model: RecordingStudioStripe::UsageEntry,
        blast_radius: :site,
        api_authorize: AUTHORIZE
      ) do
        RecordingStudioStripe::Metrics.define_usage(self)
      end
    end

    def define_subscriptions(dsl)
      dsl.count :active,
                title: "Active subscriptions",
                expose: EXPOSE,
                scope: ->(relation) { relation.merge(RecordingStudioStripe::Subscription.current) }
      dsl.breakdown :by_status, title: "Subscriptions by status", field: :status, expose: EXPOSE
      dsl.breakdown :by_plan, title: "Subscriptions by plan", field: :subscription_type, expose: EXPOSE
      dsl.timeseries :new, title: "New subscriptions", field: :created_at, expose: EXPOSE
    end

    def define_usage(dsl)
      dsl.sum :total, title: "Total usage", field: :quantity, expose: EXPOSE
      dsl.timeseries :over_time,
                     title: "Usage over time",
                     field: :recorded_at,
                     measurement: :sum,
                     value_field: :quantity,
                     expose: EXPOSE
    end
  end
end
