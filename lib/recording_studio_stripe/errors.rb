# frozen_string_literal: true

module RecordingStudioStripe
  class Error < StandardError; end
  class MissingStripeKey < Error; end
  class Forbidden < Error; end
  class InvalidPrice < Error; end
  class NoSubscription < Error; end
  class NoCustomer < Error; end

  class PlanLimitReached < Error
    attr_reader :handle

    def initialize(handle:)
      @handle = handle
      super(user_message)
    end

    def user_message
      label = handle.label.downcase
      return Copy.t("errors.pick_plan_to_add", label: label) if handle.included <= 0

      Copy.t(
        "errors.plan_includes",
        plan: plan_label,
        count: handle.included,
        label: label,
        relief: relief
      )
    end

    private

    def plan_label
      handle.product&.name.presence || Copy.t("errors.this_plan")
    end

    def relief
      return Copy.t("errors.relief_quantity") if handle.respond_to?(:quantity?) && handle.quantity?

      Copy.t("errors.relief_count")
    end
  end

  class MeterLimitReached < Error
    attr_reader :handle

    def initialize(handle:)
      @handle = handle
      super(user_message)
    end

    def user_message
      Copy.t("errors.meter_spent", label: handle.meter.label.downcase)
    end
  end

  class DeferredWebhook < Error; end

  class AmbiguousSubscriptionLine < Error
    attr_reader :meter

    def initialize(meter:)
      @meter = meter
      super("More than one live plan includes #{meter}. Use billing.line to spend on one plan.")
    end
  end

  class SubscriptionLineRequired < Error
    attr_reader :meter

    def initialize(meter:)
      @meter = meter
      super("Cannot determine which subscription line should spend #{meter}. Use billing.line(:type).")
    end
  end
end
