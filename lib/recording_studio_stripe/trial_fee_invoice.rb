# frozen_string_literal: true

module RecordingStudioStripe
  # A trial-fee invoice charges only the one-time trial Price. A zero-amount
  # plan line beside that fee is still a trial fee. Any other positive line is a real payment.
  class TrialFeeInvoice
    def self.trial_fee?(lines:, fee_price_ids:)
      new(lines: lines, fee_price_ids: fee_price_ids).trial_fee?
    end

    def initialize(lines:, fee_price_ids:)
      @lines = Array(lines)
      @fee_price_ids = Array(fee_price_ids).map(&:to_s)
    end

    def trial_fee?
      return false if @lines.empty? || @fee_price_ids.empty?
      return false unless fee_line?

      @lines.none? { |line| other_positive_line?(line) }
    end

    private

    def fee_line?
      @lines.any? { |line| @fee_price_ids.include?(price_id(line)) }
    end

    def other_positive_line?(line)
      id = price_id(line)
      id.present? && @fee_price_ids.exclude?(id) && amount(line).positive?
    end

    def price_id(line)
      (line[:price_id] || line["price_id"]).to_s
    end

    def amount(line)
      (line[:amount] || line["amount"]).to_i
    end
  end
end
