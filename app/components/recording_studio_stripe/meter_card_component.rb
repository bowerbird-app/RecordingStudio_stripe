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
        card.header do
          render FlatPack::PageTitle::Component.new(
            title: @handle.meter.label,
            subtitle: "#{stripe_quantity_label(@handle.remaining)} left",
            variant: :h3,
            class: "mb-0 pb-0"
          )
        end
        card.body { details }
      end
    end

    private

    def details
      cap = [@handle.included + @handle.purchased, 1].max
      used = [@handle.usage, cap].min
      helpers.tag.div(class: "flex flex-col gap-3") do
        safe_join(
          [
            render(FlatPack::Progress::Component.new(value: used, max: cap, style: progress_style, size: :md)),
            helpers.tag.p(breakdown, class: "text-sm text-[var(--surface-muted-content-color)]")
          ]
        )
      end
    end

    def breakdown
      included = stripe_quantity_label(@handle.included)
      bought = stripe_quantity_label(@handle.purchased)
      used = stripe_quantity_label(@handle.usage)
      "Included #{included}. Bought #{bought}. Used #{used}."
    end

    def progress_style
      return :danger if @handle.remaining <= 0
      return :warning if @handle.included.positive? && @handle.remaining < (@handle.included * 0.15)

      :default
    end
  end
end
