# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../../dummy/test/test_helper"

module RecordingStudioStripe
  class UsageMeterCardsTest < ActiveSupport::TestCase
    MeterName = Struct.new(:label, :name)
    MeterReading = Struct.new(:meter, :included, :purchased, :usage, :usage_display) do
      def remaining
        return 0 unless included.is_a?(Numeric)

        [included.to_i + purchased.to_i - usage.to_i, 0].max
      end
    end
    ActionLimit = Struct.new(:label, :included, :used, :product, :action, :action_label, :action_url, :action_method) do
      def over?
        included.is_a?(Numeric) && used > included
      end

      def remaining
        return 0 unless included.is_a?(Numeric)

        [included - used, 0].max
      end
    end
    ByteLimit = Struct.new(:label, :included, :used, :unit, :usage_display) do
      def over?
        included.is_a?(Numeric) && used > included
      end

      def remaining
        return 0 unless included.is_a?(Numeric)

        [included - used, 0].max
      end
    end
    LimitReading = Struct.new(:label, :included, :used, :usage_display) do
      def over?
        included.is_a?(Numeric) && used > included
      end

      def remaining
        return 0 unless included.is_a?(Numeric)

        [included - used, 0].max
      end
    end

    test "a meter under 80 percent uses the default usage meter" do
      html = render_meter(included: 100, usage: 40)

      assert_equal "default", bar_style(html)
      assert_includes html, "AI tokens"
      assert_includes html, "40 of 100"
      refute_includes html, "Near the limit"
      refute_includes html, "Over the limit"
    end

    test "a meter at 80 percent warns before the 15 percent status alert" do
      html = render_meter(included: 100, usage: 80)

      assert_equal "warning", bar_style(html)
      assert_includes html, "80 of 100"
      refute_includes html, "Near the limit"
    end

    test "a meter just under 80 percent stays quiet" do
      html = render_meter(included: 100, usage: 79)

      assert_equal "default", bar_style(html)
      assert_includes html, "79 of 100"
    end

    test "a meter over the cap keeps the real usage and turns danger" do
      html = render_meter(included: 100, usage: 150)

      assert_equal "danger", bar_style(html)
      assert_includes html, "150 of 100"
      refute_includes html, "Over the limit"
      refute_includes html, "Near the limit"
      refute_includes html, "100% used"
    end

    test "a meter at the cap is danger without the over alert" do
      html = render_meter(included: 100, usage: 100)

      assert_equal "danger", bar_style(html)
      assert_includes html, "100 of 100"
      refute_includes html, "Over the limit"
    end

    test "a zero meter cap uses the none-on-plan meter" do
      html = render_meter(included: 0, purchased: 0, usage: 0)

      assert_nil bar_style(html)
      assert_includes html, "AI tokens"
      assert_includes html, "None on plan"
      refute_includes html, "None on this plan"
      refute_includes html, "Unlimited"
      refute_includes html, "Over the limit"
      refute_includes html, ">Upgrade<"
      refute_includes html, ">Buy more<"
    end

    test "recorded usage on a zero meter cap stays none on plan" do
      html = render_meter(included: 0, purchased: 0, usage: 5)

      assert_nil bar_style(html)
      assert_includes html, "AI tokens"
      assert_includes html, "None on plan"
      refute_includes html, "None on this plan"
      refute_includes html, "Unlimited"
      refute_includes html, 'role="progressbar"'
    end

    test "a nil meter cap is unlimited" do
      html = render_meter(included: nil, purchased: nil, usage: 4)

      assert_nil bar_style(html)
      assert_includes html, "4 · Unlimited"
      refute_includes html, "None on this plan"
    end

    test "an allowance under the combined cap names the split" do
      html = render_meter(included: 10_000_000, purchased: 5_000_000, usage: 1_000_000)

      assert_equal "default", bar_style(html)
      assert_includes html, "1000000 of 15000000"
      assert_includes html, "10m on this plan. 5m from extra packs."
      refute_includes html, "Breakdown"
      refute_includes html, "Total this period"
    end

    test "an allowance at 80 percent of the combined cap warns on the meter" do
      html = render_meter(included: 10_000_000, purchased: 5_000_000, usage: 12_000_000)

      assert_equal "warning", bar_style(html)
      assert_includes html, "12000000 of 15000000"
      assert_includes html, "10m on this plan. 5m from extra packs."
      refute_includes html, "Near the limit"
    end

    test "an allowance over the combined cap keeps the split and turns danger" do
      html = render_meter(included: 10_000_000, purchased: 5_000_000, usage: 16_000_000)

      assert_equal "danger", bar_style(html)
      assert_includes html, "16000000 of 15000000"
      assert_includes html, "10m on this plan. 5m from extra packs."
      refute_includes html, "Over the limit"
    end

    test "a purchased allowance with nothing included is the meter cap" do
      html = render_meter(included: 0, purchased: 5_000, usage: 1_000)

      assert_equal "default", bar_style(html)
      assert_includes html, "1000 of 5000"
      refute_includes html, "from extra packs"
    end

    test "a purchased allowance at 80 percent warns" do
      html = render_meter(included: 0, purchased: 5_000, usage: 4_000)

      assert_equal "warning", bar_style(html)
      assert_includes html, "4000 of 5000"
    end

    test "a purchased allowance over the pack turns danger" do
      html = render_meter(included: 0, purchased: 5_000, usage: 6_000)

      assert_equal "danger", bar_style(html)
      assert_includes html, "6000 of 5000"
      refute_includes html, "Over the limit"
    end

    test "a limit under 80 percent uses the default usage meter" do
      html = render_limit(included: 10, used: 2)

      assert_equal "default", bar_style(html)
      assert_includes html, "Press kits"
      assert_includes html, "2 of 10"
      refute_includes html, "2/10"
    end

    test "a limit at 80 percent warns before the status alert" do
      html = render_limit(included: 10, used: 8)

      assert_equal "warning", bar_style(html)
      assert_includes html, "8 of 10"
      refute_includes html, "Near the limit"
    end

    test "a limit within 15 percent remaining does not render a status alert" do
      html = render_limit(included: 10, used: 9)

      assert_equal "warning", bar_style(html)
      assert_includes html, "9 of 10"
      refute_includes html, "Near the limit"
      refute_includes html, "Over the limit"
    end

    test "a limit over the cap keeps the real usage and skips the status alert" do
      html = render_limit(included: 10, used: 12)

      assert_equal "danger", bar_style(html)
      assert_includes html, "12 of 10"
      refute_includes html, "Over the limit"
      refute_includes html, "Near the limit"
    end

    test "a zero limit is none on plan and has no button without an action" do
      html = render_limit(included: 0, used: 0)

      assert_nil bar_style(html)
      assert_includes html, "Press kits"
      assert_includes html, "None on plan"
      refute_includes html, "None on this plan"
      refute_includes html, "Unlimited"
      refute_includes html, ">Upgrade<"
      refute_includes html, ">Buy more<"
    end

    test "a zero limit with usage stays none on plan and shows the over alert" do
      html = render_limit(included: 0, used: 2)

      assert_nil bar_style(html)
      assert_includes html, "None on plan"
      refute_includes html, "Over the limit"
      refute_includes html, "None on this plan"
      refute_includes html, "Unlimited"
    end

    test "an upgrade action without a url links to the plans page" do
      html = render_action_limit(included: 2, used: 3, action: "upgrade", action_url: nil)

      assert_includes html, 'href="/plans"'
      assert_includes html, ">Upgrade<"
    end

    test "an upgrade action is a link on an over-limit meter without an alert" do
      html = render_action_limit(included: 2, used: 3, action: "upgrade", action_url: "/plans")

      assert_includes html, "3 of 2"
      refute_includes html, "Over the limit"
      refute_includes html, "Near the limit"
      refute_includes html, "past the Press kits cap."
      refute_includes html, "This plan"
      assert_includes html, 'href="/plans"'
      assert_includes html, ">Upgrade<"
      refute_includes html, "<form"
    end

    test "an upgrade action shows on a warning bar and stays off below it" do
      warning = render_action_limit(included: 10, used: 8, action: "upgrade", action_url: "/plans")
      quiet = render_action_limit(included: 10, used: 7, action: "upgrade", action_url: "/plans")

      assert_equal "warning", bar_style(warning)
      assert_includes warning, ">Upgrade<"
      refute_includes warning, "Near the limit"
      refute_includes quiet, ">Upgrade<"
      assert_equal "default", bar_style(quiet)
    end

    test "a purchase action is a link on a zero limit" do
      html = render_action_limit(
        included: 0,
        used: 0,
        action: "purchase",
        action_label: "Buy credits",
        action_url: "/credits"
      )

      assert_includes html, "None on plan"
      assert_includes html, 'href="/credits"'
      assert_includes html, ">Buy credits<"
      refute_includes html, ">Upgrade<"
      refute_includes html, "<form"
    end

    test "a purchase action that posts uses a form submit" do
      html = render_action_limit(
        included: 0,
        used: 0,
        action: "purchase",
        action_url: "/credits",
        action_method: "post"
      )

      assert_includes html, 'action="/credits"'
      assert_includes html, 'method="post"'
      assert_includes html, ">Buy more<"
      refute_includes html, 'href="/credits"'
    end

    test "a byte quantity limit prints sizes on the meter" do
      html = render_byte_limit(included: 2.gigabytes, used: 1.gigabyte)

      assert_equal "default", bar_style(html)
      assert_includes html, "Storage"
      assert_includes html, "1 GB of 2 GB"
    end

    test "a byte quantity over the cap keeps the sizes and the over alert" do
      html = render_byte_limit(included: 2.gigabytes, used: 3.gigabytes)

      assert_equal "danger", bar_style(html)
      assert_includes html, "3 GB of 2 GB"
      refute_includes html, "Over the limit"
    end

    test "a zero byte cap uses none on plan" do
      html = render_byte_limit(included: 0, used: 2.gigabytes)

      assert_nil bar_style(html)
      assert_includes html, "Storage"
      assert_includes html, "None on plan"
      refute_includes html, "Over the limit"
      refute_includes html, "None on this plan"
    end

    test "percent display replaces the count line and keeps the bar" do
      html = render_limit(included: 4, used: 3, display: "percent")

      assert_equal "default", bar_style(html)
      assert_includes html, "75%"
      refute_includes html, "3 of 4"
      refute_includes html, "Over the limit"
    end

    test "percent display on a byte cap does not print the size line" do
      html = render_byte_limit(included: 2.gigabytes, used: 1.gigabyte, display: "percent")

      assert_equal "default", bar_style(html)
      assert_includes html, "50%"
      refute_includes html, "1 GB of 2 GB"
    end

    test "percent display on a meter reads the share of the cap" do
      html = render_meter(included: 100, usage: 80, display: "percent")

      assert_equal "warning", bar_style(html)
      assert_includes html, "80%"
      refute_includes html, "80 of 100"
      refute_includes html, "Near the limit"
    end

    test "a nil limit is unlimited" do
      html = render_limit(included: nil, used: 4)

      assert_nil bar_style(html)
      assert_includes html, "4 · Unlimited"
      refute_includes html, "None on this plan"
    end

    test "an allowance card is the pack checkout and not a usage meter" do
      RecordingStudioStripe::SeedDemoCatalog.call
      price = RecordingStudioStripe::Price.one_time.find_by!("metadata ->> 'allowance' = '5000000'")
      html = ApplicationController.render(
        AllowanceCardComponent.new(price: price),
        layout: false
      )

      assert_includes html, "Add this pack"
      assert_includes html, "+5m"
      assert_nil bar_style(html)
      refute_includes html, "Unlimited"
      refute_includes html, "None on this plan"
    end

    private

    def render_meter(included:, usage:, purchased: 0, display: nil)
      handle = MeterReading.new(
        MeterName.new("AI tokens", "ai_tokens"),
        included,
        purchased,
        usage,
        display
      )
      ApplicationController.render(MeterCardComponent.new(handle: handle), layout: false)
    end

    def render_limit(included:, used:, display: nil)
      handle = LimitReading.new("Press kits", included, used, display)
      ApplicationController.render(LimitCardComponent.new(handle: handle), layout: false)
    end

    def render_byte_limit(included:, used:, display: nil)
      handle = ByteLimit.new("Storage", included, used, "bytes", display)
      ApplicationController.render(LimitCardComponent.new(handle: handle), layout: false)
    end

    def render_action_limit(included:, used:, action:, action_url:, action_label: nil, action_method: nil)
      handle = ActionLimit.new("Press kits", included, used, nil, action, action_label, action_url, action_method)
      ApplicationController.render(LimitCardComponent.new(handle: handle), layout: false)
    end

    def bar_style(html)
      fill = Nokogiri::HTML.fragment(html).at_css("[role='progressbar'] > div")
      return if fill.nil?

      classes = fill["class"].to_s
      return "danger" if classes.include?("fp-progress-fill--danger")
      return "warning" if classes.include?("fp-progress-fill--warning")

      "default"
    end
  end
end
