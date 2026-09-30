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
        @billing.meter(@name)
      when 1
        candidates.first.meter(@name)
      else
        raise AmbiguousSubscriptionLine.new(meter: @name)
      end
    end

    private

    def candidates
      @candidates ||= @billing.active_lines.select { |entry| balance(entry).positive? }
    end

    def balance(entry)
      handle = entry.meter(@name)
      handle.included + handle.purchased
    end
  end
end
