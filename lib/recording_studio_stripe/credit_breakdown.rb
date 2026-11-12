# frozen_string_literal: true

require "json"

module RecordingStudioStripe
  module CreditBreakdown
    MAX_BYTES = 16 * 1024

    module_function

    def parse(value)
      raise ArgumentError, "breakdown must be a Hash" unless value.is_a?(Hash)

      normalized = stringify(value)
      json = JSON.generate(normalized)
      raise ArgumentError, "breakdown is too large" if json.bytesize > MAX_BYTES

      normalized
    rescue JSON::GeneratorError
      raise ArgumentError, "breakdown must be JSON"
    end

    def stringify(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), normalized|
          normalized[key.to_s] = stringify(item)
        end
      when Array
        value.map { |item| stringify(item) }
      else
        value
      end
    end
  end
end
