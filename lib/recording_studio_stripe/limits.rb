# frozen_string_literal: true

module RecordingStudioStripe
  class Limits
    class Definition
      attr_reader :name, :label, :recordable_type, :subscription_type

      def initialize(name, attrs)
        @name = name.to_s
        @label = attrs["label"].presence || @name.humanize
        @recordable_type = attrs["recordable_type"].to_s
        @subscription_type = attrs["subscription_type"].presence || implied_subscription_type
      end

      def covers_type?(type)
        recordable_type == type.to_s
      end

      private

      def implied_subscription_type
        SubscriptionTypes.known?(name) ? name : SubscriptionTypes.keys.first
      end
    end

    def self.configured?
      raw.present?
    end

    def self.all
      raw.filter_map do |name, attrs|
        next if attrs["recordable_type"].blank?

        Definition.new(name, attrs)
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
