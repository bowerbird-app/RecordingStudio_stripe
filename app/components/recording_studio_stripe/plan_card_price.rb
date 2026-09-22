# frozen_string_literal: true

module RecordingStudioStripe
  class PlanCardPrice
    PRICE_SIZE = "font-size: var(--page-title-h2-size); line-height: 1;"
    UNIT_SIZE = "font-size: var(--text-lg); line-height: 1;"

    def self.render(view:, price:, trial:, offer:)
      new(view: view, price: price, trial: trial, offer: offer).render
    end

    def initialize(view:, price:, trial:, offer:)
      @view = view
      @price = price
      @trial = trial
      @offer = offer
    end

    def render
      @view.tag.div(class: "flex flex-col items-start gap-2 py-[var(--card-padding-md)]") do
        @view.safe_join([badge, line].compact)
      end
    end

    private

    def badge
      return unless @offer

      @view.render FlatPack::Badge::Component.new(text: @trial.duration_label, style: :success, size: :sm)
    end

    def line
      @view.tag.p(class: "m-0 flex items-baseline gap-2 font-bold text-[var(--surface-content-color)]") do
        @offer ? offer_line : standard_line
      end
    end

    def standard_line
      @view.safe_join([amount(@price.formatted_amount), unit])
    end

    def offer_line
      @view.safe_join([
                        amount(@price.formatted_amount, struck: true),
                        amount(@trial.amount_label),
                        unit
                      ])
    end

    def amount(text, struck: false)
      @view.content_tag(
        struck ? :s : :span,
        text,
        class: ("text-[var(--surface-muted-content-color)]" if struck),
        style: PRICE_SIZE
      )
    end

    def unit
      @view.content_tag(:span, "/#{interval_abbrev}", style: UNIT_SIZE)
    end

    def interval_abbrev
      @price.interval == "year" ? "yr" : "mo"
    end
  end
end
