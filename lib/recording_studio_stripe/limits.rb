# frozen_string_literal: true

module RecordingStudioStripe
  class Limits
    AGGREGATIONS = %w[count quantity].freeze

    class Definition
      attr_reader :name, :label, :recordable_type, :subscription_type, :icon, :plan_line, :aggregation

      def initialize(name, attrs)
        @name = name.to_s
        @label = attrs["label"].presence || @name.humanize
        @aggregation = aggregation_mode(attrs["aggregation"])
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

      def covers_type?(type)
        count? && recordable_type == type.to_s
      end

      private

      def aggregation_mode(value)
        mode = value.presence&.to_s || "count"
        return mode if AGGREGATIONS.include?(mode)

        raise ArgumentError,
              "Unsupported aggregation #{mode.inspect} for limit #{name}. Use \"count\" or \"quantity\"."
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
