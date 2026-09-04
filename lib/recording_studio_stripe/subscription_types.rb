# frozen_string_literal: true

module RecordingStudioStripe
  class SubscriptionTypes
    IMPLIED_KEY = "plan"

    def self.configured?
      raw.present?
    end

    def self.all
      return { IMPLIED_KEY => { "label" => "Plan" } } unless configured?

      raw
    end

    def self.keys
      all.keys
    end

    def self.label(key)
      all.dig(key.to_s, "label").presence || key.to_s.humanize
    end

    def self.known?(key)
      keys.include?(key.to_s)
    end

    def self.normalize(key)
      key.to_s.presence || keys.first
    end

    def self.select_options
      keys.map { |key| [label(key), key] }
    end

    def self.raw
      hash = RecordingStudioStripe.configuration.subscription_types
      return {} if hash.blank?

      hash.to_h.stringify_keys.transform_values { |value| value.to_h.stringify_keys }
    end
    private_class_method :raw
  end
end
