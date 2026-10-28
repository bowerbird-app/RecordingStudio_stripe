# frozen_string_literal: true

module RecordingStudioStripe
  class PlanCardComponent < ViewComponent::Base
    include RecordingStudioStripe::ApplicationHelper
    include PlanCardLayout

    DENSITIES = %i[auto cards rows].freeze
    SUBGRID_ROWS = "grid row-span-4 grid-rows-subgrid"
    # Flatpack Card rejects style:, and its own flex class wins a normal grid utility.
    CARD_SUBGRID_ROWS = "h-full [display:grid]! [grid-template-rows:subgrid]! [grid-row:span_4]!"

    def initialize(product:, interval:, subscription:, density: :cards)
      super()
      @product = product
      @interval = interval
      @subscription = subscription
      @density = density.to_sym
      validate_density!
    end

    def call
      render FlatPack::Card::Component.new(
        background: :default,
        border: current? ? :default : :strong,
        shadow: current? ? :md : :none,
        class: card_class,
        data: { plan_density: @density.to_s }
      ) do |card|
        card.body(**body_options) { safe_join([title, price_row, action_row, inclusions]) }
      end
    end

    private

    def price
      @product.price_for(@interval)
    end

    def title
      return page_title if cards?

      # PageTitle sets an inline font-size, so a phone utility cannot shrink the name.
      helpers.tag.div(class: slot(:title)) do
        safe_join([name_heading, subtitle_paragraph].compact)
      end
    end

    def page_title
      render FlatPack::PageTitle::Component.new(
        title: @product.name,
        subtitle: title_subtitle,
        variant: :h3,
        class: "mb-0 pb-0"
      )
    end

    def title_subtitle
      return Copy.t("plans.no_price_yet", interval: stripe_interval_label(@interval)) unless price

      @product.card_subtitle
    end

    def price_row
      return rendered_price if price
      return helpers.tag.div if cards?

      helpers.tag.div(class: slot(:price))
    end

    def action_row
      return helpers.tag.div(class: "w-full") { action } if cards?

      helpers.tag.div(class: slot(:action)) { action }
    end

    def rendered_price
      PlanCardPrice.render(
        view: helpers,
        price: price,
        trial: @product.trial,
        offer: trial_offer?,
        **price_options
      )
    end

    def trial_offer?
      @product.trial.offered? && !current? && !@subscription&.active?
    end

    def inclusions
      return feature_list if cards?

      helpers.tag.div(class: slot(:inclusions)) do
        safe_join([disclosure, feature_frame])
      end
    end

    def feature_list
      render FlatPack::List::Component.new(spacing: :dense, divider: true) do
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
      render FlatPack::Button::Component.new(
        text: Copy.t("plans.current_plan"),
        style: :secondary,
        size: :md,
        type: "button",
        class: control_width
      )
    end

    def checkout_button
      helpers.button_to recording_studio_stripe.checkout_path,
                        params: { price_id: price.id },
                        class: checkout_outer_class,
                        form: checkout_form do
        render FlatPack::Button::Component.new(
          text: checkout_label,
          style: :primary,
          size: :md,
          type: "submit",
          class: control_width
        )
      end
    end

    def checkout_label
      trial_offer? ? Copy.t("plans.try_now") : Copy.t("plans.choose_plan")
    end

    def change_button
      render FlatPack::Button::Component.new(
        text: change_label,
        style: :primary,
        size: :md,
        href: recording_studio_stripe.subscription_change_path(price_id: price.id),
        class: control_width
      )
    end

    def change_label
      return Copy.t("plans.switch_now") unless @subscription&.price

      if ComparePrices.upgrade?(from: @subscription.price, to: price)
        Copy.t("plans.upgrade")
      else
        Copy.t("plans.downgrade")
      end
    end

    def recording_studio_stripe
      helpers.recording_studio_stripe
    end
  end
end
