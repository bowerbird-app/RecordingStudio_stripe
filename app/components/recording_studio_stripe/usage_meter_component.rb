# frozen_string_literal: true

module RecordingStudioStripe
  class UsageMeterComponent < ViewComponent::Base
    def initialize(label:, used:, limit:, description: nil)
      super()
      @label = label
      @used = used
      @limit = limit
      @description = description
    end

    def call
      render FlatPack::Billing::UsageMeter::Component.new(
        label: @label,
        used: @used,
        limit: @limit,
        description: @description
      )
    end
  end
end
