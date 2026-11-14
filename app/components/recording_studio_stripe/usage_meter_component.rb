# frozen_string_literal: true

module RecordingStudioStripe
  class UsageMeterComponent < ViewComponent::Base
    # UsageMeter's line is always "%{used} of %{limit}". Percent mode keeps that
    # component and replaces only the sentence.
    class PercentReading < FlatPack::Billing::UsageMeter::Component
      private

      def helper_text
        return super if @limit.nil? || @limit.to_i.zero?

        "#{percentage}%"
      end

      def percentage
        ((@used.to_f / @limit) * 100).round
      end
    end

    WARNING_RATIO = 0.8

    def self.needs_action?(handle)
      cap = cap_for(handle)
      return false if cap.nil?
      return true unless cap.to_i.positive?

      used = handle.respond_to?(:used) ? handle.used : handle.usage
      used.to_f / cap >= WARNING_RATIO
    end

    def self.cap_for(handle)
      if handle.respond_to?(:purchased)
        included = handle.included
        purchased = handle.purchased
        return if included.nil? && purchased.nil?

        return included.to_i + purchased.to_i
      end

      return unless handle.respond_to?(:included)
      return if handle.included.nil?

      handle.included.to_i
    end
    private_class_method :cap_for

    def initialize(label:, used:, limit:, description: nil, display: "count")
      super()
      @label = label
      @used = used
      @limit = limit
      @description = description
      @display = display.to_s
    end

    def call
      render meter_class.new(
        label: @label,
        used: @used,
        limit: @limit,
        description: @description
      )
    end

    private

    def meter_class
      @display == "percent" ? PercentReading : FlatPack::Billing::UsageMeter::Component
    end
  end
end
