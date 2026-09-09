# frozen_string_literal: true

require "test_helper"

class PlanFeaturesTest < Minitest::Test
  ProductStub = Struct.new(:subscription_type, :limits, :paywalls, :card, keyword_init: true) do
    def limit_quantity(name)
      limits.to_h.stringify_keys[name.to_s].to_i
    end

    def plan_card_settings
      (card || {}).stringify_keys
    end
  end

  PriceStub = Struct.new(:metadata, keyword_init: true) do
    def included_quantity(name)
      metadata.to_h.stringify_keys["included_#{name}"].to_i
    end
  end

  PaywallStub = Struct.new(:name, :label, keyword_init: true)

  def setup
    @previous_limits = RecordingStudioStripe.configuration.limits
    @previous_meters = RecordingStudioStripe.configuration.meters
    @previous_paywalls = RecordingStudioStripe.configuration.paywalls
    @previous_types = RecordingStudioStripe.configuration.subscription_types
    RecordingStudioStripe.configuration.subscription_types = {
      "studio" => { "label" => "Studio" }
    }
    RecordingStudioStripe.configuration.limits = {
      "press_kits" => {
        "label" => "Press kits",
        "recordable_type" => "PressKit",
        "subscription_type" => "studio",
        "icon" => "rectangle-stack",
        "plan_line" => "%<quantity>s press kits"
      }
    }
    RecordingStudioStripe.configuration.meters = {
      "ai_tokens" => { "label" => "AI tokens", "icon" => "sparkles" },
      "api_calls" => { "label" => "API calls", "icon" => "bolt" }
    }
    RecordingStudioStripe.configuration.paywalls = {
      "generate_image" => { "label" => "Generate an image", "icon" => "photo" }
    }
  end

  def teardown
    RecordingStudioStripe.configuration.limits = @previous_limits
    RecordingStudioStripe.configuration.meters = @previous_meters
    RecordingStudioStripe.configuration.paywalls = @previous_paywalls
    RecordingStudioStripe.configuration.subscription_types = @previous_types
  end

  def test_lists_limits_meters_and_paywalls
    lines = RecordingStudioStripe::PlanFeatures.for(product, price)

    assert_equal [
      "3 press kits",
      "1m ai tokens",
      "10k api calls",
      "Generate an image"
    ], lines.map(&:text)
    assert_equal %w[rectangle-stack sparkles bolt photo], lines.map(&:icon)
    assert_equal %w[limit:press_kits meter:ai_tokens meter:api_calls paywall:generate_image], lines.map(&:key)
  end

  def test_hides_a_meter_without_dropping_it_from_the_price
    hidden = product(card: { "hide" => ["meter:api_calls"] })
    lines = RecordingStudioStripe::PlanFeatures.for(hidden, price)

    refute_includes lines.map(&:key), "meter:api_calls"
    assert_includes lines.map(&:key), "meter:ai_tokens"
    assert_equal 10_000, price.included_quantity("api_calls")
  end

  def test_orders_visible_lines
    ordered = product(card: {
                        "order" => ["paywall:generate_image", "limit:press_kits", "meter:ai_tokens"]
                      })
    lines = RecordingStudioStripe::PlanFeatures.for(ordered, price)

    assert_equal %w[paywall:generate_image limit:press_kits meter:ai_tokens meter:api_calls], lines.map(&:key)
  end

  def test_appends_extras
    extra = product(card: {
                      "extras" => [{ "key" => "priority", "text" => "Someone picks up the phone", "icon" => "phone" }]
                    })
    lines = RecordingStudioStripe::PlanFeatures.for(extra, price)

    assert_equal "extra:priority", lines.last.key
    assert_equal "Someone picks up the phone", lines.last.text
    assert_equal "phone", lines.last.icon
  end

  def test_no_price_uses_seat_fallback
    lines = RecordingStudioStripe::PlanFeatures.for(product, nil)

    assert_equal ["This plan is a seat. Usage limits show up once a Price is attached."], lines.map(&:text)
  end

  def test_empty_visible_lines_use_seat_fallback
    empty = ProductStub.new(subscription_type: "studio", limits: {}, paywalls: [], card: {})
    blank = PriceStub.new(metadata: {})
    lines = RecordingStudioStripe::PlanFeatures.for(empty, blank)

    assert_equal ["A seat. Standing caps show on billing."], lines.map(&:text)
  end

  def test_plan_line_uses_short_quantity
    RecordingStudioStripe.configuration.meters = {
      "ai_tokens" => {
        "label" => "AI tokens",
        "icon" => "sparkles",
        "plan_line" => "%{quantity} AI tokens each period" # rubocop:disable Style/FormatStringToken
      }
    }
    lines = RecordingStudioStripe::PlanFeatures.for(product, price)

    assert_includes lines.map(&:text), "1m AI tokens each period"
  end

  def test_quantity_label_shortens
    assert_equal "3", RecordingStudioStripe::PlanFeatures.quantity_label(3)
    assert_equal "10k", RecordingStudioStripe::PlanFeatures.quantity_label(10_000)
    assert_equal "1m", RecordingStudioStripe::PlanFeatures.quantity_label(1_000_000)
  end

  def test_hide_options_list_caps_meters_and_paywalls
    options = RecordingStudioStripe::PlanFeatures.hide_options(subscription_type: "studio")

    assert_includes options, ["limit:press_kits", "Press kits"]
    assert_includes options, ["meter:ai_tokens", "AI tokens"]
    assert_includes options, ["paywall:generate_image", "Generate an image"]
  end

  private

  def product(card: {})
    ProductStub.new(
      subscription_type: "studio",
      limits: { "press_kits" => 3 },
      paywalls: [PaywallStub.new(name: "generate_image", label: "Generate an image")],
      card: card
    )
  end

  def price
    PriceStub.new(metadata: { "included_ai_tokens" => "1000000", "included_api_calls" => "10000" })
  end
end
