# frozen_string_literal: true

module RecordingStudioStripe
  class AllowanceCardComponent < ViewComponent::Base
    include RecordingStudioStripe::ApplicationHelper

    def initialize(price:)
      super()
      @price = price
    end

    def call
      render FlatPack::Card::Component.new(style: :flat) do |card|
        card.header do
          render FlatPack::PageTitle::Component.new(
            title: pack_title,
            subtitle: @price.formatted_amount,
            variant: :h3,
            class: "mb-0 pb-0"
          )
        end
        card.footer { buy_button }
      end
    end

    private

    def pack_title
      meter = Meter.find_by(name: @price.allowance_meter_name)
      label = meter&.label || @price.allowance_meter_name.to_s.tr("_", " ")
      "+#{stripe_quantity_label(@price.allowance_quantity)} #{label.downcase}"
    end

    def buy_button
      helpers.button_to recording_studio_stripe.allowances_path, params: { price_id: @price.id },
                                                                 class: "inline-flex" do
        render FlatPack::Button::Component.new(text: "Add this pack", style: :secondary, size: :md, type: "submit")
      end
    end

    def recording_studio_stripe
      helpers.recording_studio_stripe
    end
  end
end
