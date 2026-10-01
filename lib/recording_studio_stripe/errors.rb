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
      return "Pick a plan to add #{label}." if handle.included <= 0

      "#{plan_label} includes #{handle.included} #{label}. #{relief}"
    end

    private

    def plan_label
      handle.product&.name.presence || "This plan"
    end

    def relief
      return "Upgrade, or free some up." if handle.respond_to?(:quantity?) && handle.quantity?

      "Upgrade, or archive one."
    end
  end

  class MeterLimitReached < Error
    attr_reader :handle

    def initialize(handle:)
      @handle = handle
      super(user_message)
    end

    def user_message
      label = handle.meter.label.downcase
      "This period's #{label} are spent. Buy a pack, or wait for renewal."
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
