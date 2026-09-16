# frozen_string_literal: true

module RecordingStudioStripe
  class CancelPlan
    attr_reader :subscription

    def self.build(root_recording:, subscription_type: nil)
      subscription = LiveSubscription.find(
        root_recording: root_recording,
        subscription_type: subscription_type,
        missing_type_message: "Pick which plan to cancel."
      )
      return unless subscription

      new(subscription: subscription)
    end

    def initialize(subscription:)
      @subscription = subscription
    end

    def title
      "Cancel #{name}?"
    end

    def subtitle
      return "You keep it until #{period_end.to_fs(:long)}." if period_end

      "You keep it until this period ends."
    end

    def name
      subscription.price&.product&.name || "this plan"
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
