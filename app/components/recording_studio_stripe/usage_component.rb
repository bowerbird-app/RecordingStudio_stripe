# frozen_string_literal: true

module RecordingStudioStripe
  class UsageComponent < ViewComponent::Base
    include RecordingStudioStripe::ApplicationHelper

    def initialize(billing:, lines: nil, title: "Usage", subtitle: nil)
      super()
      @billing = billing
      @lines = Array(lines.nil? ? billing.active_lines : lines)
      @title = title
      @subtitle = subtitle || usage_subtitle(@lines)
    end

    def call
      helpers.tag.div(class: "flex w-full flex-col gap-6", data: { usage: true }) do
        helpers.safe_join([heading, body].compact)
      end
    end

    private

    def heading
      render FlatPack::PageTitle::Component.new(
        title: @title,
        subtitle: @subtitle,
        variant: :h1
      )
    end

    def body
      blocks = subscribed_blocks
      return helpers.safe_join(blocks) if blocks.any?
      return unsubscribed_meters if Meter.exists?

      empty_state
    end

    def subscribed_blocks
      @lines.filter_map { |line| line_block(line) }
    end

    def line_block(line)
      limits = billing_line_limits(line)
      meters = billing_line_meters(line)
      return if limits.empty? && meters.empty?

      parts = [
        render(FlatPack::SectionTitle::Component.new(title: usage_section_title(line))),
        cards_grid(limits, meters)
      ]
      helpers.tag.div(
        helpers.safe_join(parts),
        class: "flex w-full flex-col gap-6",
        data: { usage_line: line.subscription_type }
      )
    end

    def unsubscribed_meters
      meters = Meter.order(:name).map { |meter| @billing.meter(meter.name) }
      helpers.safe_join(
        [
          render(FlatPack::SectionTitle::Component.new(title: "Usage this period")),
          cards_grid([], meters)
        ]
      )
    end

    def cards_grid(limits, meters)
      render FlatPack::Grid::Component.new(cols: 1, gap: :lg, class: "w-full") do
        helpers.safe_join(
          limits.map { |handle| render LimitCardComponent.new(handle: handle) } +
            meters.map { |handle| render MeterCardComponent.new(handle: handle) }
        )
      end
    end

    def empty_state
      render FlatPack::EmptyState::Component.new(
        title: "Nothing to count yet",
        description: "Meters show up once staff add them.",
        icon: :inbox
      )
    end
  end
end
