# frozen_string_literal: true

module RecordingStudioStripe
  class PlanChangeComponent < ViewComponent::Base
    def initialize(change:)
      super()
      @change = change
    end

    def call
      helpers.tag.div(class: "flex w-full flex-col gap-6") do
        helpers.safe_join([heading, actions])
      end
    end

    private

    def heading
      render FlatPack::PageTitle::Component.new(
        title: @change.title,
        subtitle: @change.subtitle,
        variant: :h1
      )
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

    def recording_studio_stripe
      helpers.recording_studio_stripe
    end
  end
end
