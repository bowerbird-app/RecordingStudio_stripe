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
      assert_includes heading["class"].to_s.split, "text-center"
      assert_includes heading.at_css("h1")["class"].to_s.split, "fp-display"
      assert_nil fragment.at_css("[role='separator']")
      pill = fragment.at_css("[data-fp-style='primary']")
      assert_includes pill["class"].to_s.split, "mb-4"
      assert_nil(pill.ancestors.find { |node| node["class"].to_s.split.include?("fp-on-backdrop") })
    end

    test "each plan group starts with a backdrop rule under a display title" do
      studio = RecordingStudioStripe::Product.find_by!(name: "Pro")
      inbox = RecordingStudioStripe::Product.find_by!(name: "Inbox")
      html = ApplicationController.render(
        RecordingStudioStripe::PlansComponent.new(
          groups: [
            { key: "studio", label: "Studio", products: [studio] },
            { key: "inbox", label: "Inbox", products: [inbox] }
          ]
        ),
        layout: false
      )

      fragment = Nokogiri::HTML.fragment(html)
      heading = fragment.at_css("[data-plans-heading]")
      assert_includes heading["class"].to_s.split, "text-center"
      assert_includes heading["class"].to_s.split, "fp-on-backdrop"
      assert_includes heading.at_css("h1")["class"].to_s.split, "fp-display"
      assert_equal "Pricing", heading.at_css("h1").text

      headings = fragment.css("[data-plan-group-heading]")
      titles = headings.map { |node| node.at_css(".fp-section-title").text.squish }
      assert_equal %w[Studio Inbox], titles
      headings.each do |group_heading|
        divider = group_heading.element_children.first
        assert_equal "separator", divider["role"]
        divider_classes = divider["class"].to_s.split
        assert_empty(RecordingStudioStripe::PlansComponent::GROUP_DIVIDER_CLASS.split - divider_classes)
        assert_includes divider.next_element["class"].to_s.split, "fp-section-title"
      end
    end

    test "default density marks the page and keeps one checkout form" do
      html = render_plans(products: [RecordingStudioStripe::Product.find_by!(name: "Pro")])
      fragment = Nokogiri::HTML.fragment(html)
      root = fragment.at_css("[data-plans-align]")

      assert_equal "auto", root["data-plan-density"]
      card = fragment.at_css(".fp-card")
      assert_equal "auto", card["data-plan-density"]
      assert_equal "Pro", card.at_css("h3").text
      body = card.element_children.first
      assert_includes body["class"].to_s, "md:grid-rows-subgrid"
      assert_equal 4, body.element_children.size
      inclusions = body.element_children[3]
      details = inclusions.at_css("details")
      assert details
      assert_nil details["open"]
      assert_includes details["class"].to_s, "peer"
      assert_equal "What\u2019s included", details.at_css("summary").text.squish
      assert_equal "chevron-down", details.at_css("svg")["data-flat-pack--icon-name-value"]
      assert_empty details.css("li")
      assert_equal 1, inclusions.css("ul").size
      assert_equal 1, card.css("form[action*='checkout']").size
      assert_includes card.at_css("form")["class"].to_s.split, "max-md:w-auto"
      assert_includes card.at_css("form")["class"].to_s.split, "md:w-full"
    end

    test "auto cards hide the marketing subtitle on a phone and shrink the price" do
      html = render_plans(products: [RecordingStudioStripe::Product.find_by!(name: "Pro")])
      fragment = Nokogiri::HTML.fragment(html)
      card = fragment.at_css(".fp-card")
      regions = card.element_children.first.element_children
      name = regions[0].at_css("h3")
      subtitle = regions[0].at_css("p")

      assert_includes name["class"].to_s, "max-md:whitespace-nowrap!"
      assert_includes name["class"].to_s, "md:text-[length:var(--page-title-h3-size)]!"
      assert_includes subtitle["class"].to_s, "max-md:hidden"
      amount = regions[1].css("span").find { |node| node["class"].to_s.include?("leading-none") }
      assert amount
      assert_nil amount["style"]
      assert_includes amount["class"].to_s, "text-[length:var(--text-xl)]"
      assert_includes amount["class"].to_s, "md:text-[length:var(--page-title-h2-size)]!"
      assert_includes regions[1]["class"].to_s, "justify-end"
    end

    test "density cards keep four regions and no disclosure" do
      html = render_plans(
        products: [RecordingStudioStripe::Product.find_by!(name: "Starter")],
        density: :cards
      )
      fragment = Nokogiri::HTML.fragment(html)

      assert_equal "cards", fragment.at_css("[data-plans-align]")["data-plan-density"]
      refute fragment.at_css("details")
      card = fragment.at_css(".fp-card")
      regions = card.element_children.first.element_children
      assert_equal 4, regions.size
      assert regions[0].at_css("h3")
      assert regions[3].at_css("li")
      assert_includes html, "lg:grid-cols-3"
      assert_includes card.parent["class"].to_s, "grid-rows-subgrid"
      refute_includes card.parent["class"].to_s, "md:grid-rows-subgrid"
      refute_includes card["class"].to_s, "md:[display:grid]!"
      assert_equal 1, fragment.css("form[action*='checkout']").size
    end

    test "density rows use a collection stack and one checkout form" do
      html = render_plans(
        products: [RecordingStudioStripe::Product.find_by!(name: "Starter")],
        density: "rows"
      )
      fragment = Nokogiri::HTML.fragment(html)
      list = fragment.at_css("ul")

      assert_equal "rows", fragment.at_css("[data-plans-align]")["data-plan-density"]
      refute_includes html, "lg:grid-cols-3"
      refute_includes html, "grid-rows-subgrid"
      assert_includes list["class"].to_s, "flex-col"
      assert_includes list["class"].to_s, "gap-2"
      details = fragment.at_css("details")
      assert details
      assert_nil details["open"]
      assert_equal 1, fragment.css(".fp-card ul").size
      assert_equal 1, fragment.css("form[action*='checkout']").size
    end

    test "unknown density raises" do
      product = RecordingStudioStripe::Product.find_by!(name: "Pro")
      plans_error = assert_raises(ArgumentError) do
        RecordingStudioStripe::PlansComponent.new(products: [product], density: :grid)
      end
      card_error = assert_raises(ArgumentError) do
        RecordingStudioStripe::PlanCardComponent.new(
          product: product,
          interval: "month",
          subscription: nil,
          density: :grid
        )
      end

      assert_match(/:auto, :cards, or :rows/, plans_error.message)
      assert_match(/:auto, :cards, or :rows/, card_error.message)
      assert_equal %i[auto cards rows], RecordingStudioStripe::PlanCardComponent::DENSITIES
    end

    private

    def render_plans(products:, density: :auto)
      ApplicationController.render(
        RecordingStudioStripe::PlansComponent.new(
          products: products,
          monthly_href: "/plans",
          yearly_href: "/plans?interval=year",
          density: density
        ),
        layout: false
      )
    end
  end
end
