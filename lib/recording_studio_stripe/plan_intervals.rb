# frozen_string_literal: true

module RecordingStudioStripe
  class PlanIntervals
    INTERVALS = %w[month year].freeze
    DEFAULT = "month"

    def self.from(params)
      new(params[:interval])
    end

    def initialize(raw)
      @raw = raw
    end

    def for(key)
      if nested?
        nested_value(key) || DEFAULT
      else
        scalar || DEFAULT
      end
    end

    def query(key, value)
      chosen = normalize(value) || DEFAULT
      keys = SubscriptionTypes.keys
      return { interval: chosen } if keys.size <= 1

      current = keys.index_with { |type| self.for(type) }
      current[key.to_s] = chosen
      compact = current.reject { |_type, interval| interval == DEFAULT }
      compact.empty? ? {} : { interval: compact }
    end

    def hrefs_for(key)
      {
        interval: self.for(key),
        monthly_href: yield(query(key, "month")),
        yearly_href: yield(query(key, "year"))
      }
    end

    private

    def nested?
      @raw.is_a?(Hash) || (defined?(ActionController::Parameters) && @raw.is_a?(ActionController::Parameters))
    end

    def nested_value(key)
      normalize(@raw[key] || @raw[key.to_s] || @raw[key.to_sym])
    end

    def scalar
      normalize(@raw)
    end

    def normalize(value)
      value.to_s.presence_in(INTERVALS)
    end
  end
end
