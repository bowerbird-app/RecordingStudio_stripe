# frozen_string_literal: true

module RecordingStudioStripe
  class PlansComponent < ViewComponent::Base
    include RecordingStudioStripe::ApplicationHelper

    ALIGNS = %i[left center].freeze

    def initialize(interval: "month", monthly_href: nil, yearly_href: nil, products: [], subscription: nil,
                   groups: nil, align: :left, title: "Pick a plan",
                   subtitle: "Monthly or yearly. You can switch later.")
      super()
      @interval = interval
      @align = align.to_sym
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
      if @align == :center
        "flex w-full flex-col gap-6 items-center"
      else
        "flex w-full flex-col gap-6 items-start"
      end
    end

    def heading
      render FlatPack::PageTitle::Component.new(
        title: @title,
        subtitle: @subtitle,
        variant: :h1,
        class: "mb-0 pb-0"
      )
    end

    def groups
      blocks = @groups.filter_map { |group| group_block(group) }
      return if blocks.empty?

      helpers.tag.div(helpers.safe_join(blocks), class: groups_stack_class)
    end

    def groups_stack_class
      if @align == :center
        "flex w-full flex-col gap-10 items-center"
      else
        "flex w-full flex-col gap-10 items-start"
      end
    end

    def group_block(group)
      products = Array(group_value(group, :products))
      return if products.empty?

      subscription = group_value(group, :subscription)
      label = group_value(group, :label)
      key = group_value(group, :key)
      interval = group_value(group, :interval).presence || @interval
      monthly_href = group_value(group, :monthly_href).presence || @monthly_href
      yearly_href = group_value(group, :yearly_href).presence || @yearly_href
      parts = []
      parts << group_heading(label, interval, monthly_href, yearly_href)
      parts << cards_row(products, subscription, interval)
      attrs = { class: "flex w-full flex-col gap-4" }
      attrs[:data] = { plan_group: key } if key.present?
      helpers.tag.div(helpers.safe_join(parts.compact), **attrs)
    end

    def group_heading(label, interval, monthly_href, yearly_href)
      pills = interval_pills(interval, monthly_href, yearly_href, label)
      return pills if label.blank?

      helpers.tag.div(class: heading_row_class) do
        helpers.safe_join([section_title(label), pills].compact)
      end
    end

    def heading_row_class
      if @align == :center
        "flex w-full flex-wrap items-center justify-center gap-4"
      else
        "flex w-full flex-wrap items-center justify-between gap-4"
      end
    end

    def interval_pills(interval, monthly_href, yearly_href, label)
      return if monthly_href.blank? || yearly_href.blank?

      render FlatPack::Button::Pill::Component.new(
        items: pill_items(interval, monthly_href, yearly_href, label)
      )
    end

    def pill_items(interval, monthly_href, yearly_href, label)
      [
        pill_item("Monthly", monthly_href, interval == "month", label, "monthly"),
        pill_item("Yearly", yearly_href, interval == "year", label, "yearly")
      ]
    end

    def pill_item(text, href, active, label, cadence)
      item = { text: text, href: href, active: active }
      item[:aria] = { label: "#{label} #{cadence}" } if label.present?
      item
    end

    def section_title(label)
      render FlatPack::SectionTitle::Component.new(title: label, class: "my-0")
    end

    def cards_row(products, subscription, interval)
      helpers.tag.div(class: row_class) do
        helpers.safe_join(products.map { |product| card_for(product, subscription, interval) })
      end
    end

    def row_class
      if @align == :center
        "flex w-full flex-wrap gap-6 justify-center"
      else
        "flex w-full flex-wrap gap-6 justify-start"
      end
    end

    def card_for(product, subscription, interval)
      helpers.tag.div(class: "w-full md:w-[calc((100%-1.5rem)/2)] lg:w-[calc((100%-3rem)/3)]") do
        render PlanCardComponent.new(
          product: product,
          interval: interval,
          subscription: subscription
        )
      end
    end

    def empty_state
      return if @groups.any? { |group| Array(group_value(group, :products)).any? }

      helpers.tag.div(class: "w-full") do
        render FlatPack::EmptyState::Component.new(
          title: "No plans yet",
          description: "Staff add Products and Prices in admin. Come back when the shop is stocked.",
          icon: :inbox
        )
      end
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
