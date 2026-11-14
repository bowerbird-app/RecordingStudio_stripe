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
        description: pack_split
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

    def limit_notice
      notice = LimitStatusComponent.new(handle: @handle)
      return render(notice) if notice.render?

      helpers.stripe_limit_action(@handle) if zero_cap?
    end

    def zero_cap?
      included = @handle.included
      purchased = @handle.purchased
      return false if included.nil? && purchased.nil?

      (included.to_i + purchased.to_i) <= 0
    end
  end
end
