# frozen_string_literal: true

module RecordingStudioStripe
  class LimitStatusComponent < ViewComponent::Base
    NEAR_REMAINING_RATIO = 0.15

    def initialize(handle:)
      super()
      @handle = handle
    end

    def render?
      over? || near?
    end

    def call
      render FlatPack::Billing::StatusAlert::Component.new(
        style: over? ? :danger : :warning,
        title: Copy.t(over? ? "billing.over_limit_title" : "billing.near_limit_title"),
        description: Copy.t(
          over? ? "billing.over_limit_description" : "billing.near_limit_description",
          label: label
        )
      )
    end

    private

    def label
      @handle.respond_to?(:label) ? @handle.label : @handle.meter.label
    end

    def over?
      return @handle.over? if @handle.respond_to?(:over?)

      included = @handle.included
      return false unless included.is_a?(Numeric)

      total = included + @handle.purchased.to_i
      total.positive? && @handle.usage > total
    end

    def near?
      return false if over?

      included = @handle.included
      return false unless included.is_a?(Numeric) && included.positive?

      remaining = @handle.remaining
      remaining.positive? && remaining < (included * NEAR_REMAINING_RATIO)
    end
  end
end
