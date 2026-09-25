# frozen_string_literal: true

module RecordingStudioStripe
  class PlanIntervalPills
    ROWS = [
      %w[week Weekly weekly],
      %w[month Monthly monthly],
      %w[year Yearly yearly]
    ].freeze

    def self.items(interval:, products:, weekly_href:, monthly_href:, yearly_href:, label: nil, intervals: nil)
      new(
        interval: interval,
        products: products,
        weekly_href: weekly_href,
        monthly_href: monthly_href,
        yearly_href: yearly_href,
        label: label,
        intervals: intervals
      ).items
    end

    def initialize(interval:, products:, weekly_href:, monthly_href:, yearly_href:, label:, intervals:)
      @interval = interval.to_s
      @products = Array(products)
      @hrefs = { "week" => weekly_href, "month" => monthly_href, "year" => yearly_href }
      @label = label
      @intervals = intervals
    end

    def items
      offered = PlanIntervals.offered(@products, intervals: @intervals)
      ROWS.filter_map do |interval, text, cadence|
        href = @hrefs[interval]
        next unless offered.include?(interval) && href.present?

        item(text, href, cadence)
      end
    end

    private

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
