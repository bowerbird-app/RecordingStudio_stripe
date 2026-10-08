# frozen_string_literal: true

module RecordingStudioStripe
  class PlanIntervalPills
    ROWS = [
      %w[week weekly],
      %w[month monthly],
      %w[year yearly]
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
      ROWS.filter_map do |interval, cadence|
        href = @hrefs[interval]
        next unless offered.include?(interval) && href.present?

        item(Copy.t("intervals.pills.#{interval}"), href, cadence)
      end
    end

    private

    def item(text, href, cadence)
      row = { text: text, href: href, active: @interval == cadence_interval(cadence) }
      if @label.present?
        cadence_word = Copy.t("intervals.adjectives.#{cadence}")
        row[:aria] = { label: Copy.t("intervals.aria", label: @label, cadence: cadence_word) }
      end
      row
    end

    def cadence_interval(cadence)
      { "weekly" => "week", "monthly" => "month", "yearly" => "year" }.fetch(cadence)
    end
  end
end
