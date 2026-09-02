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
      render FlatPack::Card::Component.new(style: current? ? :elevated : :outlined) do |card|
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
      helpers.tag.ul(class: "space-y-2 text-sm leading-6") do
        safe_join(inclusion_lines.map { |line| helpers.tag.li(line) })
      end
    end

    def inclusion_lines
      return ["This plan is a seat. Usage limits show up once a Price is attached."] unless price

      lines = Meter.order(:name).filter_map do |meter|
        quantity = price.included_quantity(meter.name)
        next if quantity <= 0

        "#{stripe_quantity_label(quantity)} #{meter.label.downcase}"
      end
      lines.presence || ["Unlimited vibes. Add included usage on the Price."]
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
      helpers.button_to recording_studio_stripe.checkout_path, params: { price_id: price.id }, class: "inline-flex" do
        render FlatPack::Button::Component.new(text: "Choose plan", style: :primary, size: :md, type: "submit")
      end
    end

    def change_button
      helpers.button_to recording_studio_stripe.subscription_path, method: :patch, params: { price_id: price.id },
                                                                   class: "inline-flex" do
        render FlatPack::Button::Component.new(text: change_label, style: :primary, size: :md, type: "submit")
      end
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
