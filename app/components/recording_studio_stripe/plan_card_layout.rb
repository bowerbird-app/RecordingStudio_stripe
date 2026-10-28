# frozen_string_literal: true

module RecordingStudioStripe
  module PlanCardLayout
    private

    def name_heading
      helpers.tag.h3(@product.name, class: slot(:name))
    end

    def subtitle_paragraph
      text = title_subtitle
      return if text.blank?

      helpers.tag.p(text, class: subtitle_class)
    end

    def subtitle_class
      key = price && @product.card_subtitle.present? ? :subtitle_quiet : :subtitle
      slot(key)
    end

    def price_options
      return {} if cards?

      {
        root_class: slot(:price),
        amount_class: slot(:amount),
        unit_class: slot(:unit)
      }
    end

    def feature_frame
      helpers.tag.div(class: slot(:list_frame)) { feature_list }
    end

    def disclosure
      helpers.tag.details(class: slot(:disclosure)) do
        helpers.tag.summary(class: PlanCardDensity::SUMMARY) do
          safe_join([Copy.t("plans.included"), chevron])
        end
      end
    end

    def chevron
      render FlatPack::Shared::IconComponent.new(
        name: "chevron-down",
        size: :sm,
        class: PlanCardDensity::CHEVRON
      )
    end

    def cards?
      @density == :cards
    end

    def card_class
      cards? ? PlanCardComponent::CARD_SUBGRID_ROWS : slot(:card)
    end

    def body_options
      return { class: PlanCardComponent::SUBGRID_ROWS } if cards?

      { padding: :none, class: slot(:body) }
    end

    def control_width
      return "w-full" if cards?

      slot(:button)
    end

    def checkout_outer_class
      return PlanCardComponent::CARDS_CONTROL if cards?

      slot(:form)
    end

    def control_box(&)
      helpers.tag.div(class: checkout_outer_class, &)
    end

    def plan_button(text:, style:, type: "button", href: nil)
      options = { text: text, style: style, size: :md, type: type, class: control_width }
      options[:href] = href if href
      control_box { render FlatPack::Button::Component.new(**options) }
    end

    def slot(name)
      PlanCardDensity.slot(@density, name)
    end

    def validate_density!
      return if PlanCardComponent::DENSITIES.include?(@density)

      raise ArgumentError, "density must be :auto, :cards, or :rows"
    end
  end
end
