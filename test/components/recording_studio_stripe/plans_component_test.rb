# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../../dummy/test/test_helper"

module RecordingStudioStripe
  class PlansComponentTest < ActiveSupport::TestCase
    setup do
      RecordingStudioStripe::SeedDemoCatalog.call
    end

    test "interval pills render a primary track on the surface background" do
      studio = RecordingStudioStripe::Product.find_by!(name: "Pro")
      inbox = RecordingStudioStripe::Product.find_by!(name: "Inbox")
      html = ApplicationController.render(
        RecordingStudioStripe::PlansComponent.new(
          groups: [
            {
              key: "studio",
              label: "Studio",
              products: [studio],
              monthly_href: "/plans",
              yearly_href: "/plans?interval=year"
            },
            {
              key: "inbox",
              label: "Inbox",
              products: [inbox],
              monthly_href: "/plans?interval[inbox]=month",
              yearly_href: "/plans?interval[inbox]=year"
            }
          ]
        ),
        layout: false
      )

      fragment = Nokogiri::HTML.fragment(html)
      pills = fragment.css("[data-fp-style='primary'].fp-pill-button-slots")
      assert_equal 2, pills.size

      pills.each do |pill|
        classes = pill["class"].to_s.split
        assert_includes classes, "bg-[var(--tabs-pill-list-background-color)]"
        assert_includes classes, "border-[var(--tabs-pill-list-border-color)]"
        assert_includes classes, "p-[var(--pill-padding)]"
        assert_empty(RecordingStudioStripe::PlansComponent::PILL_TRACK_CLASS.split - classes)
        assert_includes classes, "mb-4"
        refute_includes classes, "bg-[var(--surface-background-color)]"
        assert_nil(pill.ancestors.find { |node| node["class"].to_s.split.include?("fp-on-backdrop") })
        assert_equal "primary", pill["data-fp-style"]
        assert pill.at_css("a[aria-current='page']")
        assert_includes pill.text, "Monthly"
        assert_includes pill.text, "Yearly"
      end
    end

    test "one plan group still renders the surface track under the page title" do
      product = RecordingStudioStripe::Product.find_by!(name: "Pro")
      html = ApplicationController.render(
        RecordingStudioStripe::PlansComponent.new(
          groups: [
            {
              products: [product],
              monthly_href: "/plans",
              yearly_href: "/plans?interval=year"
            }
          ]
        ),
        layout: false
      )

      fragment = Nokogiri::HTML.fragment(html)
      assert_equal 1, fragment.css("[data-fp-style='primary'].fp-pill-button-slots").size
      refute fragment.at_css("[data-plan-group-heading]")
      heading = fragment.at_css("[data-plans-heading]")
      assert_includes heading["class"].to_s.split, "fp-on-backdrop"
      pill = fragment.at_css("[data-fp-style='primary']")
      assert_includes pill["class"].to_s.split, "mb-4"
      assert_nil(pill.ancestors.find { |node| node["class"].to_s.split.include?("fp-on-backdrop") })
    end
  end
end
