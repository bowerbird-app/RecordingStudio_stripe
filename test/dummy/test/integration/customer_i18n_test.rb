# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class CustomerI18nTest < ActionDispatch::IntegrationTest
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

  test "customer pages do not render a language selector" do
    get "/"

    assert_response :success
    assert_select "form[action='/recording_studio_internationalization/locale']", count: 0

    get "/plans"

    assert_response :success
    assert_select "form[action='/recording_studio_internationalization/locale']", count: 0
    refute_includes response.body, ">English<"
    refute_includes response.body, ">Français<"
  end

  test "plans page stays English until the host locale changes" do
    get "/plans"

    assert_response :success
    assert_includes response.body, "Pricing"
    refute_includes response.body, "Monthly or yearly. You can switch later."
    assert_select "[data-plans-heading].text-center h1", text: "Pricing"
    assert_select "[data-plans-heading] p", count: 0
    assert_includes response.body, "Choose plan"
  end

  test "dummy French locale renders customer billing copy" do
    switch_to_french

    get "/plans"

    assert_response :success
    assert_includes response.body, "Tarifs"
    assert_includes response.body, "Mensuel ou annuel. Vous pourrez changer plus tard."
    assert_includes response.body, "Choisir"
    refute_includes response.body, "Monthly or yearly. You can switch later."
    assert_includes response.body, "Pro"
    assert_includes response.body, "Starter"
  end

  test "billing empty state follows French" do
    switch_to_french
    get recording_studio_stripe.root_path

    assert_response :success
    assert_includes response.body, "Facturation"
    assert_includes response.body, "Rien à facturer pour l’instant."
    assert_includes response.body, "Pas encore d’offre"
    assert_includes response.body, "Voir les tarifs"
    refute_includes response.body, "Nothing to charge yet."
  end

  test "usage page follows French" do
    switch_to_french
    get recording_studio_stripe.usage_path

    assert_response :success
    assert_includes response.body, "Conso"
    refute_includes response.body, ">Usage<"
  end

  test "a blank plans subtitle is left off the heading" do
    [ "", nil, "   " ].each do |subtitle|
      html = ApplicationController.render(
        RecordingStudioStripe::PlansComponent.new(products: [], subtitle: subtitle)
      )
      heading = Nokogiri::HTML.fragment(html).at_css("[data-plans-heading]")

      assert_equal "Pricing", heading.at_css("h1").text
      assert_nil heading.at_css("p")
    end
  end

  test "PlansComponent title override still wins" do
    html = ApplicationController.render(
      RecordingStudioStripe::PlansComponent.new(
        products: [],
        title: "Acme plans",
        subtitle: "Host copy"
      )
    )

    assert_includes html, "Acme plans"
    assert_includes html, "Host copy"
    refute_includes html, "Monthly or yearly. You can switch later."
  end

  private

  def switch_to_french
    patch "/recording_studio_internationalization/locale", params: { locale: "fr", return_to: "/" }
    follow_redirect!
  end
end
