# frozen_string_literal: true

require "test_helper"

class CancelPlanTest < Minitest::Test
  ProductStub = Struct.new(:name, keyword_init: true)
  PriceStub = Struct.new(:product, keyword_init: true)
  SubscriptionStub = Struct.new(:price, :current_period_end, :subscription_type, keyword_init: true)

  def test_cancel_copy_names_the_plan_and_the_end_date
    cancel = RecordingStudioStripe::CancelPlan.new(
      subscription: SubscriptionStub.new(
        price: PriceStub.new(product: ProductStub.new(name: "Pro")),
        current_period_end: Time.utc(2026, 10, 12),
        subscription_type: "studio"
      )
    )

    assert_equal "Cancel Pro?", cancel.title
    assert_equal "You keep it until October 12, 2026.", cancel.subtitle
    assert_equal "studio", cancel.subscription_type
  end
end
