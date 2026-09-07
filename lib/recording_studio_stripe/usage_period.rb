# frozen_string_literal: true

module RecordingStudioStripe
  class UsagePeriod
    attr_reader :root_recording, :meter, :starts_at, :ends_at

    def self.for(root_recording:, meter:, subscription_type: nil)
      subscription = Subscription.current_for(
        root_recording_id: root_recording.id,
        subscription_type: subscription_type
      )
      starts_at, ends_at = if subscription&.current_period_start && subscription.current_period_end
                             [subscription.current_period_start, subscription.current_period_end]
                           else
                             now = Time.current
                             [now.beginning_of_month, now.end_of_month]
                           end
      new(root_recording: root_recording, meter: meter, starts_at: starts_at, ends_at: ends_at,
          subscription: subscription, subscription_type: subscription_type)
    end

    def initialize(root_recording:, meter:, starts_at:, ends_at:, subscription:, subscription_type: nil)
      @root_recording = root_recording
      @meter = meter
      @starts_at = starts_at
      @ends_at = ends_at
      @subscription = subscription
      @subscription_type = subscription_type.presence || subscription&.subscription_type
    end

    def included
      return 0 unless @subscription

      @subscription.price&.included_quantity(meter.name).to_i
    end

    def purchased
      purchases = AllowancePurchase
                  .where(root_recording_id: root_recording.id, meter_id: meter.id)
                  .where(purchased_at: purchase_window_start...ends_at)
      typed_scope(purchases, AllowancePurchase).sum(:quantity)
    end

    def usage
      entries = UsageEntry
                .where(root_recording_id: root_recording.id, meter_id: meter.id)
                .where(recorded_at: starts_at...ends_at)
      typed_scope(entries, UsageEntry).sum(:quantity)
    end

    private

    def purchase_window_start
      [starts_at, starts_at.beginning_of_month].min
    end

    def typed_scope(scope, model)
      return scope if @subscription_type.blank?
      return scope unless model.column_names.include?("subscription_type")

      scope.where(subscription_type: [@subscription_type, nil, ""])
    end
  end
end
