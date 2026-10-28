# frozen_string_literal: true

module RecordingStudioStripe
  module PlansDensity
    private

    def rows_list(products, subscription, interval)
      render FlatPack::Collection::Component.new(as: :list, layout: :stack, gap: :sm, class: "w-full") do |collection|
        products.each do |product|
          collection.with_item { card_for(product, subscription, interval) }
        end
      end
    end

    def card_for(product, subscription, interval)
      helpers.tag.div(class: card_shell_class) do
        render PlanCardComponent.new(
          product: product,
          interval: interval,
          subscription: subscription,
          density: @density
        )
      end
    end

    def validate_density!
      return if PlanCardComponent::DENSITIES.include?(@density)

      raise ArgumentError, "density must be :auto, :cards, or :rows"
    end
  end
end
