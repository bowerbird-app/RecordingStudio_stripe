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
        card.body { helpers.stripe_card_stack(title, details, caption) }
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
      cap = progress_max
      render FlatPack::Progress::Component.new(
        value: [@handle.used, cap].min,
        max: cap,
        style: progress_style,
        size: :md,
        show_label: false
      )
    end

    def caption
      helpers.tag.p(caption_text, class: "text-sm leading-6")
    end

    def caption_text
      if @handle.included <= 0
        "None on this plan."
      elsif @handle.over?
        "#{@handle.used} of #{@handle.included} on this plan. Archive some, or upgrade."
      else
        "#{@handle.used} of #{@handle.included} on this plan."
      end
    end

    def progress_max
      [@handle.included, 1].max
    end

    def progress_style
      return :danger if @handle.over? || @handle.remaining <= 0
      return :warning if @handle.included.positive? && @handle.remaining < (@handle.included * 0.15)

      :default
    end
  end
end
