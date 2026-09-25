# frozen_string_literal: true

module RecordingStudioStripe
  module PlanCardDisplay
    def display_interval(group, products)
      requested = group_value(group, :interval).presence || @interval
      PlanIntervals.choose(products, requested, intervals: interval_limit(group))
    end

    def interval_limit(group)
      group_value(group, :intervals).presence || @intervals
    end

    def priced_for(products, interval)
      products.select { |product| product.price_for(interval).present? }
    end

    def group_has_cards?(group)
      raw = Array(group_value(group, :products))
      raw.any? && priced_for(raw, display_interval(group, raw)).any?
    end

    def interval_hrefs(group)
      {
        weekly: group_value(group, :weekly_href).presence || @weekly_href,
        monthly: group_value(group, :monthly_href).presence || @monthly_href,
        yearly: group_value(group, :yearly_href).presence || @yearly_href
      }
    end

    def interval_pills(interval, products, hrefs, label, intervals)
      items = PlanIntervalPills.items(
        interval: interval,
        products: products,
        weekly_href: hrefs[:weekly],
        monthly_href: hrefs[:monthly],
        yearly_href: hrefs[:yearly],
        label: label,
        intervals: intervals
      )
      return if items.empty?

      render FlatPack::Button::Pill::Component.new(items: items)
    end
  end
end
