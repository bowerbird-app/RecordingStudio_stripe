# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class HostLocaleOverrideTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @admin_root = AdminRoot.find_or_create_by!(name: "Studio Admin")
    @admin_recording = RecordingStudio.root_recording_for(@admin_root)
    grant_owner_access!(recording: @admin_recording, actor: @user)
    sign_in @user
    switch_to_root!(@admin_recording)
  end

  test "host en.yml override wins over gem english on admin form" do
    get RecordingStudioStripe.configuration.mount_path + "/admin/products/new"

    assert_response :success
    assert_includes response.body, "Host icon tip wins"
    refute_includes response.body, "A Flatpack icon name. Blank is a check."
    assert_equal "Host icon tip wins",
                 I18n.t("recording_studio.stripe.admin.plan_card.icon_help")
  end
end
