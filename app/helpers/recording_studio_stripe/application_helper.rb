# frozen_string_literal: true

module RecordingStudioStripe
  module ApplicationHelper
    STRIPE_MARK_PATH = "M13.976 9.15c-2.172-.806-3.356-1.426-3.356-2.409 0-.831.683-1.305 " \
                       "1.901-1.305 2.227 0 4.515.858 6.09 1.631l.89-5.494C18.252.975 15.697 0 " \
                       "12.165 0 9.667 0 7.589.654 6.104 1.872 4.56 3.147 3.732 4.866 3.732 7.05c0 " \
                       "4.067 2.562 5.76 6.724 7.217 2.415.83 3.23 1.426 3.23 2.332 0 .971-.846 " \
                       "1.534-2.378 1.534-1.877 0-4.956-.921-6.99-2.109l-.9 5.555C5.23 22.99 8.48 " \
                       "24 11.963 24c2.648 0 4.852-.624 6.376-1.813 1.699-1.305 2.577-3.373 " \
                       "2.577-5.828 0-4.096-2.571-5.72-6.94-7.209z"

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

    def stripe_mark
      tag.svg(
        xmlns: "http://www.w3.org/2000/svg",
        viewBox: "0 0 24 24",
        class: "inline-block h-5 w-5 shrink-0",
        fill: "currentColor",
        aria: { hidden: true }
      ) do
        tag.path(d: STRIPE_MARK_PATH)
      end
    end

    def manage_billing_on_stripe_label
      safe_join([stripe_mark, "Manage billing on Stripe"], " ")
    end
  end
end
