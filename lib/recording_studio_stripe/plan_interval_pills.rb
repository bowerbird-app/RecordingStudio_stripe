# frozen_string_literal: true

module RecordingStudioStripe
  class PlanIntervalPills
    def self.items(interval:, products:, weekly_href:, monthly_href:, yearly_href:, label: nil)
      new(
        interval: interval,
        products: products,
        weekly_href: weekly_href,
        monthly_href: monthly_href,
        yearly_href: yearly_href,
        label: label
      ).items
    end

    def initialize(interval:, products:, weekly_href:, monthly_href:, yearly_href:, label:)
      @interval = interval.to_s
      @products = Array(products)
      @weekly_href = weekly_href
      @monthly_href = monthly_href
      @yearly_href = yearly_href
      @label = label
    end

    def items
      list = []
      list << item("Weekly", @weekly_href, "weekly") if weekly?
      list << item("Monthly", @monthly_href, "monthly")
      list << item("Yearly", @yearly_href, "yearly")
      list
    end

    private

    def weekly?
      @weekly_href.present? && @products.any? { |product| product.weekly_price.present? }
    end

    def item(text, href, cadence)
      row = { text: text, href: href, active: @interval == cadence_interval(cadence) }
      row[:aria] = { label: "#{@label} #{cadence}" } if @label.present?
      row
    end

    def cadence_interval(cadence)
      { "weekly" => "week", "monthly" => "month", "yearly" => "year" }.fetch(cadence)
    end
  end
end
