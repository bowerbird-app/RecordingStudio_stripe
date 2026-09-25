# frozen_string_literal: true

require "test_helper"

class PlanIntervalPillsTest < Minitest::Test
  Product = Struct.new(:weekly_price)

  def test_weekly_stays_hidden_without_a_weekly_price
    labels = labels_for(pills(products: [Product.new(nil)]))

    assert_equal %w[Monthly Yearly], labels
  end

  def test_weekly_shows_when_a_product_has_a_weekly_price
    items = pills(products: [Product.new(Object.new)], interval: "week")

    assert_equal %w[Weekly Monthly Yearly], labels_for(items)
    assert items.first[:active]
    refute items[1][:active]
  end

  def test_weekly_stays_hidden_without_a_weekly_href
    labels = labels_for(pills(products: [Product.new(Object.new)], weekly_href: nil))

    assert_equal %w[Monthly Yearly], labels
  end

  def test_group_label_names_the_weekly_cadence
    items = pills(products: [Product.new(Object.new)], label: "Studio", interval: "week")

    assert_equal "Studio weekly", items.first[:aria][:label]
    assert_equal "Studio monthly", items[1][:aria][:label]
    assert_equal "Studio yearly", items[2][:aria][:label]
  end

  private

  def labels_for(items)
    items.map { |item| item[:text] }
  end

  def pills(products:, interval: "month", weekly_href: "/plans?interval=week", label: nil)
    RecordingStudioStripe::PlanIntervalPills.items(
      interval: interval,
      products: products,
      weekly_href: weekly_href,
      monthly_href: "/plans",
      yearly_href: "/plans?interval=year",
      label: label
    )
  end
end
