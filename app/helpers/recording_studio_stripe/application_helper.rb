# frozen_string_literal: true

module RecordingStudioStripe
  module ApplicationHelper
    def stripe_quantity_label(quantity)
      PlanFeatures.quantity_label(quantity)
    end

    def stripe_interval_label(interval)
      key = { "year" => "year", "week" => "week" }.fetch(interval.to_s, "month")
      Copy.t("intervals.names.#{key}")
    end

    def stripe_plan_intervals(products, intervals: nil)
      PlanIntervals.offered(products, intervals: intervals)
    end

    def stripe_plan_feature_lines(product, price)
      PlanFeatures.for(product, price)
    end

    def stripe_plan_inclusion_lines(product, price)
      stripe_plan_feature_lines(product, price).map(&:text)
    end

    def stripe_card_stack(*parts)
      tag.div(safe_join(parts.compact), class: "flex h-full flex-col gap-4")
    end

    def billing_subtitle(lines)
      active = Array(lines).select(&:subscribed?)
      return Copy.t("billing.nothing_to_charge") if active.empty?
      return single_line_subtitle(active.first.subscription) if active.size == 1

      names = active.map { |line| line.subscription.price&.product&.name }.compact
      Copy.t("billing.on_plans", names: names.to_sentence)
    end

    def single_line_subtitle(subscription)
      return canceling_subtitle(subscription) if subscription.canceling?
      return past_due_subtitle(subscription) if subscription.past_due?
      return trial_subtitle(subscription) if subscription.trialing?
      return scheduled_subtitle(subscription) if subscription.scheduled_downgrade?

      Copy.t("billing.on_plan", name: subscription.price&.product&.name)
    end

    def canceling_subtitle(subscription)
      Copy.t("billing.canceling", date: Copy.long_date(subscription.current_period_end))
    end

    def past_due_subtitle(subscription)
      Copy.t("billing.past_due", name: subscription.price&.product&.name)
    end

    def trial_subtitle(subscription)
      date = subscription.current_period_end
      return Copy.t("billing.on_plan", name: subscription.price&.product&.name) unless date

      price = subscription.price
      labeled_date = Copy.long_date(date)
      return Copy.t("billing.trial_until", date: labeled_date) unless price

      amount = Copy.t(
        "intervals.amount",
        amount: price.formatted_amount,
        interval: stripe_interval_label(price.interval)
      )
      Copy.t("billing.trial_until_then", date: labeled_date, amount: amount)
    end

    def scheduled_subtitle(subscription)
      Copy.t("billing.scheduled", name: subscription.scheduled_price.product.name)
    end

    def usage_subtitle(lines)
      active = Array(lines).select(&:subscribed?)
      return Copy.t("usage.resets_when_paid") if active.empty?

      ends = active.filter_map { |line| line.subscription&.current_period_end }.uniq
      return Copy.t("usage.resets_each_period") unless ends.size == 1 && ends.first

      Copy.t("usage.resets_on", date: Copy.long_date(ends.first))
    end

    def billing_line_meters(line)
      handles = RecordingStudioStripe::Meter.order(:name).map { |meter| line.meter(meter.name) }
      return handles unless RecordingStudioStripe::SubscriptionTypes.configured?

      handles.select { |handle| handle.included.positive? || handle.purchased.positive? || handle.usage.positive? }
    end

    def billing_line_limits(line)
      RecordingStudioStripe::Limits.for_subscription_type(line.subscription_type).filter_map do |definition|
        handle = line.limit(definition.name)
        handle if handle.included.positive? || handle.used.positive?
      end
    end

    def usage_in_use?(billing)
      return false unless billing.subscribed?

      billing.active_lines.any? { |line| line_has_recorded_usage?(line) }
    end

    def line_has_recorded_usage?(line)
      billing_line_meters(line).any? { |handle| handle.usage.positive? } ||
        billing_line_limits(line).any? { |handle| handle.used.positive? }
    end

    def limit_field_value(name)
      submitted = params.dig(:limits, name)
      return submitted unless submitted.nil?
      return unless defined?(@product) && @product

      quantity = @product.limit_quantity(name)
      quantity.positive? ? quantity.to_s : nil
    end

    def included_field_value(name)
      submitted = params.dig(:included, name)
      return submitted unless submitted.nil?
      return unless defined?(@price) && @price

      quantity = @price.included_quantity(name)
      quantity.positive? ? quantity.to_s : nil
    end

    def stripe_plan_card_open?(product)
      return false unless product.respond_to?(:plan_card_settings)

      settings = product.plan_card_settings
      Array(settings["hide"]).any? || Array(settings["order"]).any? || Array(settings["extras"]).any?
    end

    def stripe_plan_card_extra_rows(settings)
      rows = Array(settings.to_h.stringify_keys["extras"]).map { |extra| extra.to_h.stringify_keys }
      rows + [{}]
    end
  end
end
