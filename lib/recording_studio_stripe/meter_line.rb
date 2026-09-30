# frozen_string_literal: true

module RecordingStudioStripe
  class MeterLine
    def self.for(billing:, name:)
      new(billing, name).handle
    end

    def initialize(billing, name)
      @billing = billing
      @name = name.to_s
    end

    def handle
      case candidates.size
      when 0
        unscoped_handle
      when 1
        candidates.first.meter(@name)
      else
        raise AmbiguousSubscriptionLine.new(meter: @name)
      end
    end

    private

    def unscoped_handle
      raise SubscriptionLineRequired.new(meter: @name) if SubscriptionTypes.keys.size > 1

      @billing.meter(@name)
    end

    def candidates
      @candidates ||= @billing.active_lines.select { |entry| balance(entry).positive? }
    end

    def balance(entry)
      handle = entry.meter(@name)
      handle.included + handle.purchased
    end
  end
end
