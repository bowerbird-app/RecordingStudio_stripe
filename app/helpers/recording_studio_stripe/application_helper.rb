# frozen_string_literal: true

module RecordingStudioStripe
  module ApplicationHelper
    def stripe_quantity_label(quantity)
      number = quantity.to_i
      return number.to_s if number < 1_000
      return "#{number / 1_000}k" if number < 1_000_000

      "#{number / 1_000_000}m"
    end

    def stripe_interval_label(interval)
      interval == "year" ? "year" : "month"
    end

    def stripe_plan_inclusion_lines(product, price)
      return ["This plan is a seat. Usage limits show up once a Price is attached."] unless price

      lines = product.limit_inclusion_lines
      lines += Meter.order(:name).filter_map do |meter|
        quantity = price.included_quantity(meter.name)
        next if quantity <= 0

        "#{stripe_quantity_label(quantity)} #{meter.label.downcase}"
      end
      lines.presence || ["A seat. Standing caps show on billing."]
    end

    def stripe_card_stack(*parts)
      tag.div(safe_join(parts.compact), class: "flex h-full flex-col gap-4")
    end

    def billing_subtitle(lines)
      active = Array(lines).select(&:subscribed?)
      return "Usage resets when a paid period starts." if active.empty?
      return single_line_subtitle(active.first.subscription) if active.size == 1

      names = active.map { |line| line.subscription.price&.product&.name }.compact
      "You’re on #{names.to_sentence}."
    end

    def single_line_subtitle(subscription)
      return "This plan runs until #{subscription.current_period_end.to_date.to_fs(:long)}." if subscription.canceling?
      if subscription.scheduled_downgrade?
        return "Next period switches to #{subscription.scheduled_price.product.name}."
      end

      "You’re on #{subscription.price&.product&.name}."
    end

    def usage_section_title(line)
      return "#{line.label} usage" if RecordingStudioStripe::SubscriptionTypes.configured?

      "Usage this period"
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
  end
end
