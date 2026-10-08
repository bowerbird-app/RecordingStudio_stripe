# frozen_string_literal: true

module RecordingStudioStripe
  class CancelPlan
    attr_reader :subscription

    def self.build(root_recording:, subscription_type: nil)
      subscription = LiveSubscription.find(
        root_recording: root_recording,
        subscription_type: subscription_type,
        missing_type_message: Copy.t("alerts.pick_which_cancel")
      )
      return unless subscription

      new(subscription: subscription)
    end

    def initialize(subscription:)
      @subscription = subscription
    end

    def title
      Copy.t("cancel.heading", name: name)
    end

    def subtitle
      return Copy.t("cancel.subtitle_until", date: Copy.long_date(period_end)) if period_end

      Copy.t("cancel.subtitle_period")
    end

    def name
      subscription.price&.product&.name || Copy.t("cancel.this_plan")
    end

    def subscription_type
      subscription.subscription_type
    end

    private

    def period_end
      subscription.current_period_end&.to_date
    end
  end
end
