# frozen_string_literal: true

module RecordingStudioStripe
  class PlanChangeComponent < ViewComponent::Base
    include RecordingStudioStripe::ApplicationHelper

    def initialize(change:)
      super()
      @change = change
    end

    def call
      helpers.tag.div(class: "flex w-full flex-col gap-6") do
        helpers.safe_join([heading, timing, comparison, actions].compact)
      end
    end

    private

    def heading
      render FlatPack::PageTitle::Component.new(
        title: @change.title,
        variant: :h1
      )
    end

    def timing
      render FlatPack::Alert::Component.new(
        description: @change.subtitle,
        style: @change.upgrade? ? :info : :warning
      )
    end

    def comparison
      render FlatPack::Grid::Component.new(cols: 2, gap: :lg) do
        helpers.safe_join([plan_card(@change.from_price, "Now"), plan_card(@change.to_price, @change.next_badge)])
      end
    end

    def plan_card(price, badge)
      render FlatPack::Card::Component.new(style: :outlined) do |card|
        card.body do
          helpers.stripe_card_stack(
            render(FlatPack::Badge::Component.new(text: badge, style: badge == "Now" ? :info : :primary, size: :sm)),
            render(FlatPack::PageTitle::Component.new(
                     title: price.product.name,
                     subtitle: amount_for(price),
                     variant: :h3,
                     class: "mb-0 pb-0"
                   )),
            inclusion_list(price)
          )
        end
      end
    end

    def inclusion_list(price)
      helpers.tag.ul(class: "space-y-2 text-sm leading-6") do
        helpers.safe_join(stripe_plan_inclusion_lines(price.product, price).map { |line| helpers.tag.li(line) })
      end
    end

    def actions
      helpers.tag.div(class: "flex flex-wrap gap-2") do
        helpers.safe_join([confirm_button, keep_button])
      end
    end

    def confirm_button
      helpers.button_to recording_studio_stripe.subscription_path,
                        method: :patch,
                        params: { price_id: @change.to_price.id },
                        class: "inline-flex" do
        render FlatPack::Button::Component.new(text: @change.confirm_label, style: :primary, size: :md, type: "submit")
      end
    end

    def keep_button
      render FlatPack::Button::Component.new(
        text: "Keep this plan",
        style: :ghost,
        size: :md,
        href: helpers.main_app.plans_path
      )
    end

    def amount_for(price)
      "#{price.formatted_amount}/#{stripe_interval_label(price.interval)}"
    end

    def recording_studio_stripe
      helpers.recording_studio_stripe
    end
  end
end
