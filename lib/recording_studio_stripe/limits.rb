# frozen_string_literal: true

require "active_support/number_helper"

module RecordingStudioStripe
  class Limits
    AGGREGATIONS = %w[count quantity per_item].freeze
    UNITS = ["bytes"].freeze

    # A number that still compares as bytes, and prints as a size.
    # UsageMeter requires a Numeric for the bar and calls to_s for the line.
    class ShownAmount < Numeric
      def initialize(amount, text)
        super()
        @amount = Integer(amount)
        @text = text.to_s
      end

      def to_s
        @text
      end

      def to_i
        @amount
      end

      def to_f
        @amount.to_f
      end

      # Stay unequal to a raw integer so UsageMeter prints to_s ("5 GB"), not the byte count.
      def ==(other)
        other.is_a?(ShownAmount) && to_i == other.to_i
      end

      def zero?
        to_i.zero?
      end

      def <=>(other)
        to_i <=> other.to_i
      end

      def coerce(other)
        [other.to_i, @amount]
      end

      def positive?
        @amount.positive?
      end
    end

    class Definition
      ACTIONS = %w[upgrade purchase].freeze
      ACTION_METHODS = %w[get post put patch delete].freeze

      attr_reader :name, :label, :recordable_type, :subscription_type, :icon, :plan_line,
                  :aggregation, :unit, :no_plan_limit, :action, :action_label, :action_url,
                  :action_method

      def initialize(name, attrs)
        @name = name.to_s
        @label = attrs["label"].presence || @name.humanize
        @aggregation = aggregation_mode(attrs["aggregation"])
        @unit = unit_mode(attrs["unit"])
        @no_plan_limit = no_plan_limit_mode(attrs["no_plan_limit"])
        assign_action!(attrs)
        @recordable_type = attrs["recordable_type"].to_s
        @subscription_type = attrs["subscription_type"].presence || implied_subscription_type
        @icon = attrs["icon"].presence
        @plan_line = attrs["plan_line"].presence
      end

      def count?
        aggregation == "count"
      end

      def quantity?
        aggregation == "quantity"
      end

      def per_item?
        aggregation == "per_item"
      end

      def covers_type?(type)
        count? && recordable_type == type.to_s
      end

      def display_quantity(quantity)
        number = quantity.to_i
        return ActiveSupport::NumberHelper.number_to_human_size(number) if unit == "bytes"
        return number.to_s if per_item?

        PlanFeatures.quantity_label(quantity)
      end

      def shown_amount(quantity)
        return quantity unless unit == "bytes"

        ShownAmount.new(quantity, display_quantity(quantity))
      end

      def card_text(quantity)
        shown = display_quantity(quantity)
        if plan_line.present?
          format_plan_line(shown)
        elsif per_item?
          Copy.t("plans.features.per_item", quantity: shown)
        else
          Copy.t("plans.features.quantity_with_label", quantity: shown, label: label.downcase)
        end
      end

      private

      def aggregation_mode(value)
        mode = value.presence&.to_s || "count"
        return mode if AGGREGATIONS.include?(mode)

        raise ArgumentError,
              "Unsupported aggregation #{mode.inspect} for limit #{name}. " \
              "Use \"count\", \"quantity\", or \"per_item\"."
      end

      def unit_mode(value)
        unit = value.presence&.to_s
        return if unit.nil?
        return unit if UNITS.include?(unit)

        raise ArgumentError, "Unsupported unit #{unit.inspect} for limit #{name}. Use \"bytes\" or omit it."
      end

      def no_plan_limit_mode(value)
        return if value.nil?
        return value if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "no_plan_limit for limit #{name} must be a positive integer or nil."
      end

      def assign_action!(attrs)
        @action = action_mode(attrs["action"])
        @action_url = action_url_mode(attrs["action_url"])
        @action_label = action_label_mode(attrs["action_label"])
        @action_method = action_method_mode(attrs["action_method"])
      end

      def action_mode(value)
        kind = value.presence&.to_s
        return if kind.nil?
        return kind if ACTIONS.include?(kind)

        raise ArgumentError, "action for limit #{name} must be \"upgrade\", \"purchase\", or omitted."
      end

      def action_url_mode(value)
        if value.nil?
          return unless action == "purchase"

          raise ArgumentError, "action_url for limit #{name} is required when action is purchase."
        end
        return value if value.is_a?(String) && value.present?
        return value if value.respond_to?(:call)

        raise ArgumentError, "action_url for limit #{name} must be a path or a callable."
      end

      def action_label_mode(value)
        return if action.nil?

        text = value.presence&.to_s
        return text if text

        action == "purchase" ? "Buy more" : "Upgrade"
      end

      def action_method_mode(value)
        return if value.nil? || action.nil?

        verb = value.to_s.downcase
        return verb if ACTION_METHODS.include?(verb)

        raise ArgumentError, "action_method for limit #{name} must be get, post, put, patch, or delete."
      end

      def format_plan_line(shown)
        format(plan_line.to_s, quantity: shown, label: label)
      rescue KeyError, ArgumentError
        plan_line.to_s
      end

      def implied_subscription_type
        SubscriptionTypes.known?(name) ? name : SubscriptionTypes.keys.first
      end
    end

    def self.configured?
      raw.present?
    end

    def self.all
      raw.filter_map do |name, attrs|
        definition = Definition.new(name, attrs)
        next if definition.count? && definition.recordable_type.blank?

        definition
      end
    end

    def self.keys
      all.map(&:name)
    end

    def self.known?(name)
      keys.include?(name.to_s)
    end

    def self.fetch(name)
      key = name.to_s
      definition = all.find { |entry| entry.name == key }
      raise ArgumentError, "Unknown limit #{key}" unless definition

      definition
    end

    def self.for_recordable_type(type)
      all.select { |definition| definition.covers_type?(type) }
    end

    def self.for_subscription_type(type)
      all.select { |definition| definition.subscription_type == type.to_s }
    end

    def self.covers_type?(type)
      for_recordable_type(type).any?
    end

    def self.raw
      hash = RecordingStudioStripe.configuration.limits
      return {} if hash.blank?

      hash.to_h.stringify_keys.transform_values { |value| value.to_h.stringify_keys }
    end
    private_class_method :raw
  end
end
