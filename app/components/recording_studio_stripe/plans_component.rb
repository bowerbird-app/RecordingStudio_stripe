# frozen_string_literal: true

module RecordingStudioStripe
  class PlansComponent < ViewComponent::Base
    include RecordingStudioStripe::ApplicationHelper
    include RecordingStudioStripe::PlanCardDisplay

    private(*RecordingStudioStripe::PlanCardDisplay.instance_methods(false))

    ALIGNS = %i[left center].freeze

    def initialize(interval: "month", weekly_href: nil, monthly_href: nil, yearly_href: nil, intervals: nil,
                   products: [], subscription: nil, groups: nil, align: :center, title: "Pricing",
                   subtitle: "Monthly or yearly. You can switch later.")
      super()
      @interval = interval
      @align = align.to_sym
      @intervals = intervals
      @weekly_href = weekly_href
      @monthly_href = monthly_href
      @yearly_href = yearly_href
      @title = title
      @subtitle = subtitle
      @groups = Array(groups.presence || [{ products: products, subscription: subscription, label: nil }])
      validate_align!
    end

    def call
      helpers.tag.div(class: stack_class, data: { plans_align: @align }) do
        helpers.safe_join([heading, groups, empty_state].compact)
      end
    end

    private

    def stack_class
      aligned_class("flex w-full flex-col gap-6 items-center", "flex w-full flex-col gap-6 items-start")
    end

    def heading
      title = render FlatPack::PageTitle::Component.new(
        title: @title,
        subtitle: @subtitle,
        variant: :h1,
        class: (@align == :center ? "mb-0 pb-0 w-full text-center" : "mb-0 pb-0"),
        data: { plans_heading: true }
      )
      pills = shared_interval_pills
      return title if pills.blank?

      helpers.tag.div(helpers.safe_join([title, pills]), class: heading_stack_class)
    end

    def groups
      blocks = @groups.filter_map { |group| group_block(group) }
      return if blocks.empty?

      helpers.tag.div(helpers.safe_join(blocks), class: groups_stack_class)
    end

    def groups_stack_class
      aligned_class("flex w-full flex-col gap-10 items-center", "flex w-full flex-col gap-10 items-start")
    end

    def group_block(group)
      raw = Array(group_value(group, :products))
      return if raw.empty?

      interval = display_interval(group, raw)
      products = Catalog.sorted_plans(priced_for(raw, interval), interval: interval)
      return if products.empty?

      subscription = group_value(group, :subscription)
      label = group_value(group, :label)
      key = group_value(group, :key)
      parts = []
      parts << group_heading(label, interval, raw, interval_hrefs(group), interval_limit(group))
      parts << cards_row(products, subscription, interval)
      attrs = { class: "flex w-full flex-col gap-4" }
      attrs[:data] = { plan_group: key } if key.present?
      helpers.tag.div(helpers.safe_join(parts.compact), **attrs)
    end

    def group_heading(label, interval, products, hrefs, intervals)
      return unless show_group_headings?

      pills = interval_pills(interval, products, hrefs, label, intervals)
      title = (section_title(label) if label.present?)
      return if title.blank? && pills.blank?

      helpers.tag.div(
        helpers.safe_join([title, pills].compact),
        class: heading_stack_class,
        data: { plan_group_heading: true }
      )
    end

    def shared_interval_pills
      return if show_group_headings?

      group = populated_groups.first
      return unless group

      raw = Array(group_value(group, :products))
      interval_pills(
        display_interval(group, raw),
        raw,
        interval_hrefs(group),
        nil,
        interval_limit(group)
      )
    end

    def show_group_headings?
      populated_groups.many?
    end

    def populated_groups
      @groups.select { |group| Array(group_value(group, :products)).any? }
    end

    def heading_stack_class
      aligned_class("flex w-full flex-col items-center gap-3", "flex w-full flex-col items-start gap-3")
    end

    def section_title(label)
      render FlatPack::SectionTitle::Component.new(
        title: label,
        class: (@align == :center ? "my-0 text-center" : "my-0")
      )
    end

    def cards_row(products, subscription, interval)
      render FlatPack::Grid::Component.new(cols: 3, gap: :lg, align: :stretch, class: "w-full") do
        helpers.safe_join(products.map { |product| card_for(product, subscription, interval) })
      end
    end

    def card_for(product, subscription, interval)
      helpers.tag.div(class: "h-full") do
        render PlanCardComponent.new(
          product: product,
          interval: interval,
          subscription: subscription
        )
      end
    end

    def empty_state
      return if @groups.any? { |group| group_has_cards?(group) }

      helpers.tag.div(class: "w-full") do
        render FlatPack::EmptyState::Component.new(
          title: "No prices yet",
          description: "Staff add Products and Prices in admin. Come back when the shop is stocked.",
          icon: :inbox
        )
      end
    end

    def aligned_class(center, left)
      @align == :center ? center : left
    end

    def group_value(group, key)
      group[key] || group[key.to_s]
    end

    def validate_align!
      return if ALIGNS.include?(@align)

      raise ArgumentError, "align must be :left or :center"
    end
  end
end
