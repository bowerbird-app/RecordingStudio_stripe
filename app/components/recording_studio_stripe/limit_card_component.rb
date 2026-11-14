# frozen_string_literal: true

module RecordingStudioStripe
  class LimitCardComponent < ViewComponent::Base
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
        label: @handle.label,
        used: @handle.used,
        limit: limit_amount
      )
    end

    def limit_amount
      included = @handle.included
      return nil if included.nil?

      included.to_i
    end

    def limit_notice
      notice = LimitStatusComponent.new(handle: @handle)
      render(notice) if notice.render?
    end
  end
end
