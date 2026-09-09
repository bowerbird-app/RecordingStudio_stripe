# frozen_string_literal: true

module RecordingStudioStripe
  class PlanCardComponent < ViewComponent::Base
    include RecordingStudioStripe::ApplicationHelper

    def initialize(product:, interval:, subscription:)
      super()
      @product = product
      @interval = interval
      @subscription = subscription
    end

    def call
      render FlatPack::Card::Component.new(style: current? ? :elevated : :outlined, class: "h-full") do |card|
        card.body { helpers.stripe_card_stack(title, inclusions, action) }
      end
    end

    private

    def price
      @interval == "year" ? @product.annual_price : @product.monthly_price
    end

    def title
      render FlatPack::PageTitle::Component.new(
        title: @product.name,
        subtitle: price_subtitle,
        variant: :h3,
        class: "mb-0 pb-0"
      )
    end

    def price_subtitle
      return "No #{stripe_interval_label(@interval)} Price yet" unless price

      "#{price.formatted_amount}/#{stripe_interval_label(price.interval)}"
    end

    def inclusions
      render FlatPack::List::Component.new(spacing: :dense) do
        safe_join(feature_lines.map { |line| feature_item(line) })
      end
    end

    def feature_lines
      helpers.stripe_plan_feature_lines(@product, price)
    end

    def feature_item(line)
      render FlatPack::List::Item.new(icon: line.icon.presence || "check", class: "px-0 py-1") do
        line.text
      end
    end

    def action
      return unless price
      return current_button if current?
      return change_button if @subscription&.active?

      checkout_button
    end

    def current?
      @subscription&.price_id == price&.id
    end

    def current_button
      render FlatPack::Button::Component.new(text: "Current plan", style: :secondary, size: :md, type: "button")
    end

    def checkout_button
      helpers.button_to recording_studio_stripe.checkout_path,
                        params: { price_id: price.id },
                        class: "inline-flex",
                        form: { data: { turbo: false } } do
        render FlatPack::Button::Component.new(text: "Choose plan", style: :primary, size: :md, type: "submit")
      end
    end

    def change_button
      render FlatPack::Button::Component.new(
        text: change_label,
        style: :primary,
        size: :md,
        href: recording_studio_stripe.subscription_change_path(price_id: price.id)
      )
    end

    def change_label
      return "Switch now" unless @subscription&.price

      ComparePrices.upgrade?(from: @subscription.price, to: price) ? "Upgrade" : "Switch at renewal"
    end

    def recording_studio_stripe
      helpers.recording_studio_stripe
    end
  end
end
