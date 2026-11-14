# frozen_string_literal: true

module RecordingStudioStripe
  class MeterCardComponent < ViewComponent::Base
    include RecordingStudioStripe::ApplicationHelper

    def initialize(handle:)
      super()
      @handle = handle
    end

    def call
      render FlatPack::Card::Component.new(background: :default, border: :strong, shadow: :none) do |card|
        card.body { helpers.stripe_card_stack(meter, limit_notice) }
      end
    end

    private

    def meter
      render UsageMeterComponent.new(
        label: @handle.meter.label,
        used: @handle.usage,
        limit: meter_limit,
        description: pack_split,
        display: usage_display
      )
    end

    def meter_limit
      included = @handle.included
      purchased = @handle.purchased
      return nil if included.nil? && purchased.nil?

      included.to_i + purchased.to_i
    end

    def pack_split
      return unless @handle.included.to_i.positive? && @handle.purchased.to_i.positive?

      Copy.t(
        "usage.pack_split",
        included: stripe_quantity_label(@handle.included),
        purchased: stripe_quantity_label(@handle.purchased)
      )
    end

    def usage_display
      return "count" unless @handle.respond_to?(:usage_display)

      @handle.usage_display.presence || "count"
    end

    def limit_notice
      helpers.stripe_usage_action(@handle)
    end
  end
end
