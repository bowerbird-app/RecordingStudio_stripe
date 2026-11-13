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
      return zero_limit if @limit.is_a?(Numeric) && !@limit.positive?

      render FlatPack::Billing::UsageMeter::Component.new(
        label: @label,
        used: @used,
        limit: @limit,
        description: @description
      )
    end

    private

    def zero_limit
      render FlatPack::Text::Component.new(text: zero_copy, size: :sm, style: :muted)
    end

    def zero_copy
      return Copy.t("usage.none_named", label: @label) unless @used.to_i.positive?

      Copy.t("usage.used_none_on_plan", label: @label, used: @used.to_i)
    end
  end
end
