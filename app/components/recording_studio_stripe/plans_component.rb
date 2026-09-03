# frozen_string_literal: true

module RecordingStudioStripe
  class PlansComponent < ViewComponent::Base
    include RecordingStudioStripe::ApplicationHelper

    ALIGNS = %i[left center].freeze

    def initialize(products:, interval:, monthly_href:, yearly_href:, subscription: nil, align: :left,
                   title: "Pick a plan", subtitle: "Monthly or yearly. You can switch later.")
      super()
      @products = products
      @interval = interval
      @subscription = subscription
      @align = align.to_sym
      @monthly_href = monthly_href
      @yearly_href = yearly_href
      @title = title
      @subtitle = subtitle
      validate_align!
    end

    def call
      helpers.tag.div(class: stack_class, data: { plans_align: @align }) do
        helpers.safe_join([heading, interval_pills, cards].compact)
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

    def interval_pills
      render FlatPack::Button::Pill::Component.new(
        items: [
          { text: "Monthly", href: @monthly_href, active: @interval == "month" },
          { text: "Yearly", href: @yearly_href, active: @interval == "year" }
        ]
      )
    end

    def cards
      return empty_state if @products.empty?

      helpers.tag.div(class: row_class) do
        helpers.safe_join(@products.map { |product| card_for(product) })
      end
    end

    def row_class
      if @align == :center
        "flex w-full flex-wrap gap-6 justify-center"
      else
        "flex w-full flex-wrap gap-6 justify-start"
      end
    end

    def card_for(product)
      helpers.tag.div(class: "w-full md:w-[calc((100%-1.5rem)/2)] lg:w-[calc((100%-3rem)/3)]") do
        render PlanCardComponent.new(
          product: product,
          interval: @interval,
          subscription: @subscription
        )
      end
    end

    def empty_state
      helpers.tag.div(class: "w-full") do
        render FlatPack::EmptyState::Component.new(
          title: "No plans yet",
          description: "Staff add Products and Prices in admin. Come back when the shop is stocked.",
          icon: :inbox
        )
      end
    end

    def validate_align!
      return if ALIGNS.include?(@align)

      raise ArgumentError, "align must be :left or :center"
    end
  end
end
