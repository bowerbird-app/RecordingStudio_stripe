# frozen_string_literal: true

module RecordingStudioStripe
  module Billable
    extend ActiveSupport::Concern

    included do |base|
      RecordingStudioStripe.register_capabilities!
      RecordingStudio.enable_capability(:stripe, on: base)
      RecordingStudio.enable_capability(:accessible, on: base) if defined?(RecordingStudioAccessible)
    end

    def billing
      RecordingStudioStripe::Billing.for(self)
    end
  end

  module RecordingBilling
    def billing
      RecordingStudioStripe::Billing.for_recording(self)
    end
  end
end
