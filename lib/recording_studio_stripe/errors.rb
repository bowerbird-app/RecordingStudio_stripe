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
      plan = handle.product&.name
      if handle.included <= 0
        "Pick a plan to add #{label}."
      elsif plan
        "#{plan} includes #{handle.included} #{label}. Upgrade, or archive one."
      else
        "This plan includes #{handle.included} #{label}. Upgrade, or archive one."
      end
    end
  end
end
