# frozen_string_literal: true

module RecordingStudioStripe
  class MeterCardComponent < ViewComponent::Base
    include RecordingStudioStripe::ApplicationHelper

    def initialize(handle:)
      super()
      @handle = handle
    end

    def call
      render FlatPack::Card::Component.new(style: :outlined) do |card|
        card.body { helpers.stripe_card_stack(heading, details) }
      end
    end

    private

    def heading
      return title unless combined?

      helpers.tag.div(class: "flex items-start justify-between gap-4") do
        helpers.safe_join([title, breakdown])
      end
    end

    def title
      render FlatPack::PageTitle::Component.new(
        title: @handle.meter.label,
        variant: :h3,
        class: "mb-0 pb-0"
      )
    end

    def combined?
      @handle.included.positive? && @handle.purchased.positive?
    end

    def breakdown
      render FlatPack::Button::Dropdown::Component.new(
        text: "Breakdown",
        style: :default,
        size: :md,
        placement: :bottom_right
      ) do |dropdown|
        dropdown.menu_item(text: "On this plan", badge: stripe_quantity_label(@handle.included))
        dropdown.menu_item(text: "Extra packs", badge: stripe_quantity_label(@handle.purchased))
        dropdown.menu_divider
        dropdown.menu_item(text: "Total this period", badge: stripe_quantity_label(period_total))
      end
    end

    def period_total
      @handle.included + @handle.purchased
    end

    def details
      cap = [period_total, 1].max
      used = [@handle.usage, cap].min
      render FlatPack::Progress::Component.new(
        value: used,
        max: cap,
        style: progress_style,
        size: :md,
        show_label: true
      )
    end

    def progress_style
      return :default if period_total.zero?
      return :danger if @handle.remaining <= 0
      return :warning if @handle.included.positive? && @handle.remaining < (@handle.included * 0.15)

      :default
    end
  end
end
