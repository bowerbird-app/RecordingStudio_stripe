# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class DefaultLayoutBackgroundTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_owner_access!(recording: @root, actor: @user)
    sign_in @user
    switch_to_root!(@root)
  end

  test "plans keeps the default layout and leaves the backdrop unset" do
    get "/plans"

    assert_response :success
    assert_plans_on_default_layout
    assert_select "[data-fp-page-layout-width=default]", count: 1
    assert_select "[data-flat-pack-layout-background]", count: 0
    assert_select ".fp-backdrop", count: 0
    assert_select ".fp-backdrop-media img", count: 0
  end

  test "plans paints a background image and page width from the layout helpers" do
    with_plans_slot_probe do
      get "/plans", params: { background_image: "/icon.png", page_width: "wide" }
    end

    assert_response :success
    assert_plans_on_default_layout
    assert_select "[data-fp-page-layout-width=wide]", count: 1
    assert_background_image "/icon.png"
  end

  test "plans paints a background image and page width from content_for" do
    with_plans_slot_probe do
      get "/plans", params: { slot: "content_for", background_image: "/icon.png", page_width: "narrow" }
    end

    assert_response :success
    assert_plans_on_default_layout
    assert_select "[data-fp-page-layout-width=narrow]", count: 1
    assert_background_image "/icon.png"
  end

  test "a blank background image and page width leave the plans layout unchanged" do
    with_plans_slot_probe do
      get "/plans", params: { background_image: "", page_width: "" }
    end

    assert_response :success
    assert_plans_on_default_layout
    assert_select "[data-fp-page-layout-width=default]", count: 1
    assert_select "[data-flat-pack-layout-background]", count: 0
    assert_select ".fp-backdrop-media img", count: 0
  end

  private

  def with_plans_slot_probe
    controller = RecordingStudioStripe::PlansController
    original_paths = controller.view_paths.dup
    controller.prepend_view_path(Rails.root.join("test/views"))
    yield
  ensure
    controller.view_paths = original_paths
    leaked = controller.view_paths.any? { |path| path.to_s.end_with?("test/views") }
    flunk "plans probe view path leaked" if leaked
  end

  def assert_plans_on_default_layout
    assert_select "html[data-theme=rounded]", count: 1
    assert_select "body[data-recording-studio-default-layout=true]", count: 1
    assert_select "h1", text: "Pricing", count: 1
  end

  def assert_background_image(src)
    assert_select "[data-flat-pack-layout-background='true'].fp-layout-main .fp-backdrop[aria-hidden='true']", count: 1
    assert_select ".fp-backdrop-media img[alt=''][loading='lazy'][src='#{src}']", count: 1
    assert_select ".fp-backdrop-tint", count: 1
  end
end
