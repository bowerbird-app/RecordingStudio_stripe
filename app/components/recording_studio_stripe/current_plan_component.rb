# frozen_string_literal: true

module RecordingStudioStripe
  class CurrentPlanComponent < ViewComponent::Base
    include RecordingStudioStripe::ApplicationHelper

    def initialize(subscription:)
      super()
      @subscription = subscription
    end

    def call
      render FlatPack::Card::Component.new(style: :default) do |card|
        card.header do
          render FlatPack::PageTitle::Component.new(
            title: @subscription.price&.product&.name || "Current plan",
            subtitle: period_copy,
            variant: :h3,
            class: "mb-0 pb-0"
          )
        end
        card.body { badges }
        card.footer { actions }
      end
    end

    private

    def period_copy
      price = @subscription.price
      return "Stripe is catching up." unless price

      "#{price.formatted_amount}/#{stripe_interval_label(price.interval)}"
    end

    def badges
      parts = []
      parts << if @subscription.canceling?
                 render(FlatPack::Badge::Component.new(text: "Ends this period", style: :warning, size: :sm))
               elsif @subscription.scheduled_downgrade?
                 render(FlatPack::Badge::Component.new(text: "Change scheduled", style: :info, size: :sm))
               else
                 render(FlatPack::Badge::Component.new(text: "Active", style: :success, size: :sm))
               end
      helpers.tag.div(safe_join(parts), class: "flex flex-wrap gap-2")
    end

    def actions
      helpers.tag.div(class: "flex flex-wrap gap-2") do
        safe_join(
          [
            render(FlatPack::Button::Component.new(text: "Change plan", style: :secondary, size: :md,
                                                   href: main_app.plans_path)),
            cancel_or_resume
          ]
        )
      end
    end

    def cancel_or_resume
      if @subscription.canceling?
        helpers.button_to recording_studio_stripe.subscription_resume_path, class: "inline-flex" do
          render FlatPack::Button::Component.new(text: "Keep this plan", style: :primary, size: :md, type: "submit")
        end
      else
        helpers.button_to recording_studio_stripe.subscription_cancel_path, class: "inline-flex" do
          render FlatPack::Button::Component.new(text: "Cancel", style: :ghost, size: :md, type: "submit")
        end
      end
    end

    def main_app
      helpers.main_app
    end

    def recording_studio_stripe
      helpers.recording_studio_stripe
    end
  end
end
