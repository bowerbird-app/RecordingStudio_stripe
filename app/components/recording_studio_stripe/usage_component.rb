# frozen_string_literal: true

module RecordingStudioStripe
  class UsageComponent < ViewComponent::Base
    include RecordingStudioStripe::ApplicationHelper

    def initialize(billing:, lines: nil, title: Copy::UNSET, subtitle: nil)
      super()
      @billing = billing
      @lines = Array(lines.nil? ? billing.active_lines : lines)
      @title = title
      @subtitle = subtitle
    end

    def call
      helpers.tag.div(class: "flex w-full flex-col gap-6", data: { usage: true }) do
        helpers.safe_join([heading, body].compact)
      end
    end

    private

    def heading
      return if @title.nil?

      render FlatPack::PageTitle::Component.new(
        title: Copy.value(@title, "usage.title"),
        subtitle: @subtitle || usage_subtitle(@lines),
        variant: :h1
      )
    end

    def body
      blocks = subscribed_blocks
      bases = unsubscribed_limit_blocks
      return helpers.safe_join(blocks + bases) if blocks.any?
      return helpers.safe_join(bases + [unsubscribed_meters].compact) if bases.any? && Meter.exists?
      return helpers.safe_join(bases) if bases.any?
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

      helpers.tag.div(
        cards_grid(limits, meters),
        class: "w-full",
        data: { usage_line: line.subscription_type }
      )
    end

    def unsubscribed_meters
      meters = Meter.order(:name).map { |meter| @billing.meter(meter.name) }
      cards_grid([], meters)
    end

    def unsubscribed_limit_blocks
      active_types = Array(@lines).map { |line| line.subscription_type.to_s }
      @billing.lines.reject { |line| active_types.include?(line.subscription_type.to_s) }.filter_map do |line|
        limits = billing_line_limits(line)
        next if limits.empty?

        helpers.tag.div(
          cards_grid(limits, []),
          class: "w-full",
          data: { usage_line: line.subscription_type }
        )
      end
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
        title: Copy.t("usage.empty_title"),
        description: Copy.t("usage.empty_description"),
        icon: :inbox
      )
    end
  end
end
