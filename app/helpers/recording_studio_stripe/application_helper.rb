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

    def stripe_card_stack(*parts)
      tag.div(safe_join(parts.compact), class: "flex h-full flex-col gap-4")
    end

    def billing_subtitle(subscription)
      return "Usage resets when a paid period starts." unless subscription&.active?
      return "This plan runs until #{subscription.current_period_end.to_date.to_fs(:long)}." if subscription.canceling?
      if subscription.scheduled_downgrade?
        return "Next period switches to #{subscription.scheduled_price.product.name}."
      end

      "You’re on #{subscription.price&.product&.name}."
    end
  end
end
