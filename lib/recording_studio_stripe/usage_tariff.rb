# frozen_string_literal: true

module RecordingStudioStripe
  class UsageTariff
    Charge = Data.define(:key, :quantity, :rate, :credits)

    def self.rate(key)
      name = string_key(key)
      value = RecordingStudioStripe.configuration.usage_costs[name]
      raise ArgumentError, "Unknown usage #{name.inspect}" if value.nil?

      value
    end

    def self.charge(key:, quantity: 1)
      name = string_key(key)
      count = positive_integer(quantity, "quantity")
      unit = rate(name)
      Charge.new(key: name, quantity: count, rate: unit, credits: count * unit)
    end

    def self.normalize_costs(costs)
      raise ArgumentError, "usage_costs must be a Hash" unless costs.is_a?(Hash)

      costs.each_with_object({}) do |(key, value), normalized|
        name = string_key(key)
        normalized[name] = positive_integer(value, "usage cost for #{name.inspect}")
      end
    end

    def self.string_key(key)
      raise ArgumentError, "usage key must be a String" unless key.is_a?(String)
      raise ArgumentError, "usage key must not be blank" if key.strip.empty?

      key
    end

    def self.positive_integer(value, label)
      return value if value.is_a?(Integer) && value.positive?

      raise ArgumentError, "#{label} must be a positive integer"
    end
    private_class_method :string_key, :positive_integer
  end
end
