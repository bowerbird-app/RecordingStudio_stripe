# frozen_string_literal: true

require "test_helper"

class TrialFeeInvoiceTest < Minitest::Test
  def test_fee_line_alone_is_a_trial_fee
    assert trial_fee?([{ price_id: "price_fee", amount: 100 }], ["price_fee"])
  end

  def test_fee_plus_a_zero_plan_line_is_still_a_trial_fee
    lines = [
      { price_id: "price_fee", amount: 100 },
      { price_id: "price_plan", amount: 0 }
    ]

    assert trial_fee?(lines, ["price_fee"])
  end

  def test_a_positive_plan_line_is_a_real_payment
    lines = [
      { price_id: "price_fee", amount: 100 },
      { price_id: "price_plan", amount: 2900 }
    ]

    refute trial_fee?(lines, ["price_fee"])
  end

  def test_a_plan_line_without_the_fee_is_a_real_payment
    refute trial_fee?([{ price_id: "price_plan", amount: 2900 }], ["price_fee"])
  end

  def test_a_positive_line_without_a_price_id_is_not_a_trial_fee
    lines = [
      { price_id: "price_fee", amount: 100 },
      { price_id: "", amount: 50 }
    ]

    refute trial_fee?(lines, ["price_fee"])
  end

  def test_blank_lines_are_not_a_trial_fee
    refute trial_fee?([], ["price_fee"])
    refute RecordingStudioStripe::TrialFeeInvoice.trial_fee?(lines: [{ price_id: "price_fee", amount: 100 }],
                                                             fee_price_ids: [])
  end

  private

  def trial_fee?(lines, fee_price_ids)
    RecordingStudioStripe::TrialFeeInvoice.trial_fee?(lines: lines, fee_price_ids: fee_price_ids)
  end
end
