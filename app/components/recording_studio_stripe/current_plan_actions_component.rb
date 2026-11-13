# frozen_string_literal: true

module RecordingStudioStripe
  class CurrentPlanActionsComponent < ViewComponent::Base
    def initialize(subscription:, can_manage:)
      super()
      @subscription = subscription
      @can_manage = can_manage
      @state = CurrentPlanState.new(subscription)
    end

    def call
      safe_join(pieces)
    end

    private

    def pieces
      @pieces ||= [extra_badges, *action_buttons].compact
    end

    def extra_badges
      badges = []
      badges << badge(Copy.t("billing.ends_this_period"), :warning) if @state.show_period_end?
      badges << badge(Copy.t("billing.change_scheduled"), :info) if @state.scheduled_change?
      return if badges.empty?

      safe_join(badges)
    end

    def badge(text, style)
      render FlatPack::Badge::Component.new(text: text, style: style, size: :sm)
    end

    def action_buttons
      [update_card_button, stay_button, change_plan_button, keep_plan_button, cancel_link]
    end

    def change_plan_button
      render FlatPack::Button::Component.new(
        text: Copy.t("billing.change_plan"),
        style: :secondary,
        size: :md,
        href: helpers.main_app.plans_path
      )
    end

    def update_card_button
      return unless manageable? && @state.past_due?

      helpers.stripe_action_form(helpers.recording_studio_stripe.portal_path, turbo: false) do
        submit_button(Copy.t("billing.update_card"))
      end
    end

    def stay_button
      return unless manageable? && @state.scheduled_change?

      helpers.stripe_action_form(
        helpers.recording_studio_stripe.subscription_keep_path,
        hidden: { subscription_type: @state.subscription_type }
      ) do
        submit_button(stay_label)
      end
    end

    def stay_label
      name = @subscription.price&.product&.name
      name.present? ? Copy.t("billing.stay_on_named", name: name) : Copy.t("billing.stay_on_this")
    end

    def keep_plan_button
      return unless manageable? && @state.show_period_end?

      helpers.stripe_action_form(
        helpers.recording_studio_stripe.subscription_resume_path,
        hidden: { subscription_type: @state.subscription_type }
      ) do
        submit_button(Copy.t("billing.keep_this_plan"))
      end
    end

    def cancel_link
      return unless manageable? && !@state.canceling?

      render FlatPack::Button::Component.new(
        text: Copy.t("billing.cancel"),
        style: :ghost,
        size: :md,
        href: helpers.recording_studio_stripe.subscription_cancel_confirm_path(
          subscription_type: @state.subscription_type
        )
      )
    end

    def submit_button(text)
      render FlatPack::Button::Component.new(text: text, style: :primary, size: :md, type: "submit")
    end

    def manageable?
      @can_manage && !@state.canceled?
    end
  end
end
