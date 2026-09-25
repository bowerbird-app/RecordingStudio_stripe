# frozen_string_literal: true

module RecordingStudioStripe
  class PlanCardPrice
    ABBREV = { "year" => "yr", "week" => "wk" }.freeze
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
      price_with_unit(@price.formatted_amount)
    end

    def offer_line
      @view.safe_join([
                        price_with_unit(@price.formatted_amount, struck: true),
                        trial_amount
                      ])
    end

    def price_with_unit(text, struck: false)
      @view.content_tag(struck ? :s : :span, class: price_group_class(struck)) do
        @view.safe_join([amount(text), unit])
      end
    end

    def price_group_class(struck)
      classes = ["inline-flex items-baseline"]
      classes << "text-[var(--surface-muted-content-color)]" if struck
      classes.join(" ")
    end

    def trial_amount
      @view.content_tag(:span, class: "inline-flex items-baseline") do
        @view.safe_join([amount(@trial.amount_label), trial_word])
      end
    end

    def amount(text)
      @view.content_tag(:span, text, style: PRICE_SIZE)
    end

    def unit
      @view.content_tag(:span, "/#{interval_abbrev}", style: UNIT_SIZE)
    end

    def trial_word
      @view.content_tag(:span, "trial", style: "#{UNIT_SIZE} margin-left: 0.25em;")
    end

    def interval_abbrev
      ABBREV.fetch(@price.interval, "mo")
    end
  end
end
