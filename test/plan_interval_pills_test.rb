# frozen_string_literal: true

require "test_helper"

class PlanIntervalPillsTest < Minitest::Test
  Product = Struct.new(:priced) do
    def price_for(interval)
      priced.to_h[interval.to_s]
    end
  end

  def test_only_intervals_with_a_price_show
    labels = labels_for(pills(products: [product("month" => :month, "year" => :year)]))

    assert_equal %w[Monthly Yearly], labels
  end

  def test_weekly_shows_when_a_product_has_a_weekly_price
    items = pills(products: [product("week" => :week, "month" => :month, "year" => :year)], interval: "week")

    assert_equal %w[Weekly Monthly Yearly], labels_for(items)
    assert items.first[:active]
    refute items[1][:active]
  end

  def test_weekly_stays_hidden_without_a_weekly_href
    labels = labels_for(pills(products: [product("week" => :week, "month" => :month)], weekly_href: nil))

    assert_equal %w[Monthly], labels
  end

  def test_a_missing_yearly_price_hides_yearly
    labels = labels_for(pills(products: [product("month" => :month)]))

    assert_equal %w[Monthly], labels
  end

  def test_intervals_limit_hides_a_priced_interval
    labels = labels_for(
      pills(products: [product("week" => :week, "month" => :month, "year" => :year)], intervals: %w[month])
    )

    assert_equal %w[Monthly], labels
  end

  def test_group_label_names_the_weekly_cadence
    items = pills(
      products: [product("week" => :week, "month" => :month, "year" => :year)],
      label: "Studio",
      interval: "week"
    )

    assert_equal "Studio weekly", items.first[:aria][:label]
    assert_equal "Studio monthly", items[1][:aria][:label]
    assert_equal "Studio yearly", items[2][:aria][:label]
  end

  private

  def product(priced)
    Product.new(priced)
  end

  def labels_for(items)
    items.map { |item| item[:text] }
  end

  def pills(products:, interval: "month", weekly_href: "/plans?interval=week", intervals: nil, label: nil)
    RecordingStudioStripe::PlanIntervalPills.items(
      interval: interval,
      products: products,
      weekly_href: weekly_href,
      monthly_href: "/plans",
      yearly_href: "/plans?interval=year",
      intervals: intervals,
      label: label
    )
  end
end
