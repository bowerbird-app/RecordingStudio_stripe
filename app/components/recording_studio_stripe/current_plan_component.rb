# frozen_string_literal: true

module RecordingStudioStripe
  class CurrentPlanComponent < ViewComponent::Base
    include RecordingStudioStripe::ApplicationHelper

    def initialize(subscription:, can_manage: true)
      super()
      @subscription = subscription
      @can_manage = can_manage
    end

    def call
      render FlatPack::Card::Component.new(style: :default) do |card|
        card.body { helpers.stripe_card_stack(badges, title, actions) }
      end
    end

    private

    def title
      render FlatPack::PageTitle::Component.new(
        title: @subscription.price&.product&.name || "Current plan",
        subtitle: period_copy,
        variant: :h3,
        class: "mb-0 pb-0"
      )
    end

    def period_copy
      price = @subscription.price
      return "Stripe is catching up." unless price

      "#{price.formatted_amount}/#{stripe_interval_label(price.interval)}"
    end

    def badges
      helpers.tag.div(safe_join(badge_parts), class: "flex flex-wrap gap-2")
    end

    def badge_parts
      parts = []
      if RecordingStudioStripe::SubscriptionTypes.configured?
        parts << badge(@subscription.subscription_type_label, :info)
      end
      parts.concat(status_badges)
      parts
    end

    def status_badges
      parts = []
      parts << badge("Past due", :danger) if @subscription.past_due?
      parts << badge("Trial", :info) if @subscription.trialing?
      if @subscription.canceling?
        parts << badge("Ends this period", :warning)
      elsif @subscription.scheduled_downgrade?
        parts << badge("Change scheduled", :info)
      elsif !@subscription.past_due? && !@subscription.trialing?
        parts << badge("Active", :primary)
      end
      parts
    end

    def badge(text, style)
      render FlatPack::Badge::Component.new(text: text, style: style, size: :sm)
    end

    def actions
      helpers.tag.div(class: "flex flex-wrap gap-2") { safe_join(action_buttons) }
    end

    def action_buttons
      [
        update_card_button,
        stay_button,
        change_plan_button,
        keep_plan_button,
        cancel_link
      ].compact
    end

    def change_plan_button
      render FlatPack::Button::Component.new(text: "Change plan", style: :secondary, size: :md,
                                             href: main_app.plans_path)
    end

    def update_card_button
      return unless @can_manage && @subscription.past_due?

      helpers.button_to recording_studio_stripe.portal_path,
                        class: "inline-flex",
                        form: { data: { turbo: false } } do
        render FlatPack::Button::Component.new(text: "Update card", style: :primary, size: :md, type: "submit")
      end
    end

    def stay_button
      return unless @can_manage && @subscription.scheduled_downgrade? && !@subscription.canceling?

      helpers.button_to recording_studio_stripe.subscription_keep_path,
                        params: { subscription_type: @subscription.subscription_type },
                        class: "inline-flex" do
        render FlatPack::Button::Component.new(text: stay_label, style: :primary, size: :md, type: "submit")
      end
    end

    def stay_label
      name = @subscription.price&.product&.name
      name.present? ? "Stay on #{name}" : "Stay on this plan"
    end

    def keep_plan_button
      return unless @can_manage && @subscription.canceling?

      helpers.button_to recording_studio_stripe.subscription_resume_path,
                        params: { subscription_type: @subscription.subscription_type },
                        class: "inline-flex" do
        render FlatPack::Button::Component.new(text: "Keep this plan", style: :primary, size: :md, type: "submit")
      end
    end

    def cancel_link
      return unless @can_manage && !@subscription.canceling?

      render FlatPack::Button::Component.new(
        text: "Cancel",
        style: :ghost,
        size: :md,
        href: recording_studio_stripe.subscription_cancel_confirm_path(
          subscription_type: @subscription.subscription_type
        )
      )
    end

    def main_app
      helpers.main_app
    end

    def recording_studio_stripe
      helpers.recording_studio_stripe
    end
  end
end
