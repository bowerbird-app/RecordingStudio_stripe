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
        description: description
      ) do |alert|
        button = action_button
        alert.actions { button } if button
      end
    end

    private

    def label
      @handle.respond_to?(:label) ? @handle.label : @handle.meter.label
    end

    def description
      Copy.t(description_key, label: label)
    end

    def description_key
      return "billing.over_limit_no_plan" if over? && !on_a_plan?
      return "billing.over_limit_description" if over?

      "billing.near_limit_description"
    end

    def on_a_plan?
      return true unless @handle.respond_to?(:product)

      @handle.product&.plan?
    end

    def action_button
      helpers.stripe_limit_action(@handle)
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
