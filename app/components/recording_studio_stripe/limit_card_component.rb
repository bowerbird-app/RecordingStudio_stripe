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
        used: shown(@handle.used),
        limit: shown_limit
      )
    end

    def shown_limit
      amount = limit_amount
      return nil if amount.nil?
      return amount unless amount.positive?

      shown(amount)
    end

    def shown(amount)
      return amount unless bytes?

      text = if @handle.respond_to?(:display_quantity)
               @handle.display_quantity(amount)
             else
               ActiveSupport::NumberHelper.number_to_human_size(amount.to_i)
             end
      Limits::ShownAmount.new(amount.to_i, text)
    end

    def bytes?
      @handle.respond_to?(:unit) && @handle.unit == "bytes"
    end

    def limit_amount
      included = @handle.included
      return nil if included.nil?

      included.to_i
    end

    def limit_notice
      notice = LimitStatusComponent.new(handle: @handle)
      return render(notice) if notice.render?

      helpers.stripe_limit_action(@handle) if zero_cap?
    end

    def zero_cap?
      amount = @handle.included
      amount.is_a?(Numeric) && !amount.to_i.positive?
    end
  end
end
