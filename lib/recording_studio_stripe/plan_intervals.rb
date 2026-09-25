# frozen_string_literal: true

module RecordingStudioStripe
  class PlanIntervals
    INTERVALS = %w[week month year].freeze
    DEFAULT = "month"

    def self.from(params)
      new(params[:interval])
    end

    def self.offered(products, intervals: nil)
      allowed = allowed_intervals(intervals)
      list = Array(products)
      allowed.select { |interval| list.any? { |product| product.price_for(interval).present? } }
    end

    def self.choose(products, requested, intervals: nil)
      available = offered(products, intervals: intervals)
      requested = requested.to_s
      return requested if available.include?(requested)

      available.first || allowed_intervals(intervals).first || DEFAULT
    end

    def self.allowed_intervals(intervals)
      names = Array(intervals.presence || INTERVALS).map(&:to_s)
      INTERVALS.select { |interval| names.include?(interval) }
    end
    private_class_method :allowed_intervals

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
        weekly_href: yield(query(key, "week")),
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
