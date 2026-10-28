# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../../dummy/test/test_helper"

module RecordingStudioStripe
  PlanSubscriptionStub = Struct.new(:price_id, :price, keyword_init: true) do
    def active?
      true
    end
  end

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
      form = card.at_css("form")
      assert_includes form["class"].to_s.split, "max-md:w-auto"
      assert_includes form["class"].to_s.split, "md:w-full"
      assert_includes form["class"].to_s.split, "flex"
      assert_includes form["class"].to_s.split, "flex-col"
      assert_equal 1, form.css("button").size
      refute_includes form.at_css("button")["class"].to_s.split, "flex-col"
      regions = body.element_children
      assert_includes regions[2]["class"].to_s, "justify-start"
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
      refute_includes regions[1]["class"].to_s, "justify-start"
      assert_includes regions[1]["class"].to_s, "md:pt-8"
      assert_includes regions[1]["class"].to_s, "md:pb-4"
      refute_includes regions[1]["class"].to_s, "md:pb-8"
      assert_includes regions[1]["class"].to_s, "max-md:py-2"
      name_badge = regions[0].css("span").find { |node| node.text.include?("14 day trial") }
      assert name_badge
      assert_includes name_badge["class"].to_s, "md:hidden"
      assert regions[1].at_css("[class*='max-md:hidden']")
      assert_includes regions[2]["class"].to_s, "justify-start"
    end

    test "a card without a trial offer keeps the shared price padding" do
      html = render_plans(products: [RecordingStudioStripe::Product.find_by!(name: "Starter")])
      fragment = Nokogiri::HTML.fragment(html)
      regions = fragment.at_css(".fp-card").element_children.first.element_children
      price = regions[1]

      assert_includes price["class"].to_s, "justify-end"
      refute_includes price["class"].to_s, "justify-start"
      assert_includes price["class"].to_s, "md:pb-4"
      refute_includes price["class"].to_s, "md:pt-8"
      refute_includes regions[0].text, "14 day trial"
    end

    test "rows put the trial badge after the plan name" do
      html = render_plans(products: [RecordingStudioStripe::Product.find_by!(name: "Pro")], density: :rows)
      fragment = Nokogiri::HTML.fragment(html)
      regions = fragment.at_css(".fp-card").element_children.first.element_children
      title = regions[0]
      price = regions[1]

      assert_includes title.at_css("h3").next_element.text, "14 day trial"
      refute_includes price.text, "14 day trial"
      assert_includes price["class"].to_s.split, "py-2"
    end

    test "current and upgrade wrap in the same outer box as checkout" do
      pro = RecordingStudioStripe::Product.find_by!(name: "Pro")
      starter = RecordingStudioStripe::Product.find_by!(name: "Starter")
      subscription = PlanSubscriptionStub.new(price_id: pro.price_for("month").id, price: pro.price_for("month"))

      current_html = ApplicationController.render(
        RecordingStudioStripe::PlanCardComponent.new(
          product: pro,
          interval: "month",
          subscription: subscription,
          density: :auto
        ),
        layout: false
      )
      upgrade_html = ApplicationController.render(
        RecordingStudioStripe::PlanCardComponent.new(
          product: starter,
          interval: "month",
          subscription: subscription,
          density: :auto
        ),
        layout: false
      )

      current_action = Nokogiri::HTML.fragment(current_html).at_css(".fp-card").element_children.first.element_children[2]
      upgrade_action = Nokogiri::HTML.fragment(upgrade_html).at_css(".fp-card").element_children.first.element_children[2]
      box = current_action.element_children.first

      assert_equal "DIV", box.name.upcase
      assert_includes box["class"].to_s.split, "flex"
      assert_includes box["class"].to_s.split, "flex-col"
      assert_includes box["class"].to_s.split, "md:w-full"
      assert_equal 1, box.css("button").size
      assert_nil current_action.at_css("form")
      assert_equal box["class"], upgrade_action.element_children.first["class"]
      assert_equal 1, upgrade_action.css("button, a").size
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
