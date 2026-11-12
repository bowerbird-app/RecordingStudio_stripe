# frozen_string_literal: true

module RecordingStudioStripe
  module Api
    module Serialize
      module_function

      def billing(record)
        {
          root_id: record.root_recording.id,
          subscribed: record.subscribed?,
          lines: record.lines.map { |line| billing_line(line) }
        }
      end

      def billing_line(line)
        {
          subscription_type: line.subscription_type,
          label: line.label,
          subscribed: line.subscribed?,
          subscription: subscription(line.subscription)
        }
      end

      def plan_groups(groups)
        { groups: groups.map { |group| plan_group(group) } }
      end

      def plan_group(group)
        {
          key: group[:key],
          label: group[:label],
          products: Array(group[:products]).map { |product| plan_product(product) }
        }
      end

      def plan_product(product)
        {
          id: product.id,
          name: product.name,
          kind: product.kind,
          subscription_type: product.subscription_type,
          prices: product.prices.active.order(:interval, :unit_amount).map { |price| plan_price(price) }
        }
      end

      def plan_price(price)
        {
          id: price.id,
          interval: price.interval,
          unit_amount: price.unit_amount,
          currency: price.currency,
          active: price.active?
        }
      end

      def subscription(record)
        return if record.nil?

        {
          id: record.id,
          status: record.status,
          subscription_type: record.subscription_type,
          cancel_at_period_end: record.cancel_at_period_end,
          price_id: record.price_id,
          scheduled_price_id: record.scheduled_price_id,
          current_period_end: record.current_period_end
        }
      end

      def checkout(result)
        result.slice(:url, :session_id, :changed, :confirming, :local)
      end

      def portal(result)
        result.slice(:url, :local, :unavailable)
      end
    end
  end
end
