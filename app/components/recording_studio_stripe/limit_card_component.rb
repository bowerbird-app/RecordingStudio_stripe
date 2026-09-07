# frozen_string_literal: true

module RecordingStudioStripe
  class LimitCardComponent < ViewComponent::Base
    include RecordingStudioStripe::ApplicationHelper

    def initialize(handle:)
      super()
      @handle = handle
    end

    def call
      render FlatPack::Card::Component.new(style: :outlined) do |card|
        card.body { helpers.stripe_card_stack(title, details) }
      end
    end

    private

    def title
      render FlatPack::PageTitle::Component.new(
        title: @handle.label,
        variant: :h3,
        class: "mb-0 pb-0"
      )
    end

    def details
      cap = [@handle.included, 1].max
      used = [@handle.used, cap].min
      render FlatPack::Progress::Component.new(
        value: used,
        max: cap,
        style: progress_style,
        size: :md,
        show_label: true
      )
    end

    def progress_style
      return :danger if @handle.over? || @handle.remaining <= 0
      return :warning if @handle.included.positive? && @handle.remaining < (@handle.included * 0.15)

      :default
    end
  end
end
