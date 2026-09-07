# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class PlanLimitsTest < ActionDispatch::IntegrationTest
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

  test "starter product includes three press kits and pro includes ten" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter")
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro")
    inbox = RecordingStudioStripe::Product.find_by!(name: "Inbox")

    assert_equal 3, starter.limit_quantity("press_kits")
    assert_equal 10, pro.limit_quantity("press_kits")
    assert_equal 0, inbox.limit_quantity("press_kits")
    assert_equal ["3 press kits"], starter.limit_inclusion_lines
    assert_equal ["10 press kits"], pro.limit_inclusion_lines
  end

  test "billing limit counts live press kits against the studio plan" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: starter)
    record_press_kit!("Launch kit")
    record_press_kit!("Second kit")

    kits = @workspace.billing.limit(:press_kits)
    studio = @workspace.billing.line(:studio).limit(:press_kits)

    assert_equal 3, kits.included
    assert_equal 2, kits.used
    assert_equal 1, kits.remaining
    assert kits.available?(1)
    refute kits.available?(2)
    refute kits.over?
    assert_equal kits.included, studio.included
    assert_equal kits.used, studio.used
  end

  test "creating a press kit without a plan redirects to plans" do
    assert_no_difference -> { PressKit.count } do
      post press_kits_path, params: { name: "Launch kit" }
    end

    assert_redirected_to "/plans"
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Pick a plan to add press kits."
  end

  test "creating a fourth press kit on starter redirects to plans" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: starter)
    3.times { |index| record_press_kit!("Kit #{index + 1}") }

    assert_no_difference -> { PressKit.count } do
      post press_kits_path, params: { name: "Kit 4" }
    end

    assert_redirected_to "/plans"
    follow_redirect!
    assert_includes response.body, "Starter includes 3 press kits. Upgrade, or archive one."
  end

  test "creating a fourth press kit as json returns 403" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: starter)
    3.times { |index| record_press_kit!("Kit #{index + 1}") }

    post press_kits_path, params: { name: "Kit 4" }, as: :json

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "plan_limit_reached", body.fetch("code")
    assert_includes body.fetch("message"), "Starter includes 3 press kits"
  end

  test "revise does not consume a press kit slot" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: starter)
    recordings = 3.times.map { |index| record_press_kit!("Kit #{index + 1}") }

    @root.revise(recordings.first) do |kit|
      kit.name = "Renamed kit"
    end

    assert_equal 3, @workspace.billing.limit(:press_kits).used
    assert_equal "Renamed kit", recordings.first.reload.recordable.name
  end

  test "restore from trash is blocked when the plan is full" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: starter)
    recordings = 3.times.map { |index| record_press_kit!("Kit #{index + 1}") }
    archived = recordings.first
    archived.update_column(:trashed_at, Time.current)

    assert_equal 2, @workspace.billing.limit(:press_kits).used
    record_press_kit!("Replacement")
    assert_equal 3, @workspace.billing.limit(:press_kits).used

    error = assert_raises(RecordingStudioStripe::PlanLimitReached) do
      archived.update!(trashed_at: nil)
    end
    assert_includes error.user_message, "Starter includes 3 press kits"
    assert archived.reload.trashed_at.present?
  end

  test "folders are not gated by the press kit limit" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: starter)
    3.times { |index| record_press_kit!("Kit #{index + 1}") }

    assert_difference -> { Folder.count }, 1 do
      @root.record(Folder) { |folder| folder.name = "Still allowed" }
    end
  end

  test "billing shows the standing cap without listing or creating press kits" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: starter)
    record_press_kit!("Launch kit")

    get recording_studio_stripe.root_path

    assert_response :success
    assert_includes response.body, "Press kits"
    refute_includes response.body, "Launch kit"
    refute_includes response.body, "Add press kit"

    get "/"

    assert_response :success
    assert_includes response.body, "Press kits"
    refute_includes response.body, "Launch kit"
    refute_includes response.body, "Add press kit"

    get press_kits_path

    assert_response :success
    assert_includes response.body, "Launch kit"
    assert_includes response.body, "Add press kit"
    assert_includes response.body, "1 of 3 on this plan."
    refute_includes response.body, "Studio usage"
  end

  test "over-cap billing copy shows used of included" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)
    4.times { |index| record_press_kit!("Kit #{index + 1}") }
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: starter)

    get recording_studio_stripe.root_path

    assert_response :success
    assert_includes response.body, "4 of 3 on this plan. Archive some, or upgrade."
    kits = @workspace.billing.limit(:press_kits)
    assert kits.over?
    refute kits.available?(1)
  end

  test "pro includes ten press kits on the billing handle" do
    pro = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: pro)

    kits = @workspace.billing.limit(:press_kits)
    assert_equal 10, kits.included
    assert kits.available?(10)
    refute kits.available?(11)
  end

  test "press kits under a folder still use the workspace cap" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: starter)
    folder_recording = @root.record(Folder) { |folder| folder.name = "Kits" }
    folder_recording.record(PressKit) { |kit| kit.name = "Nested kit" }

    assert_equal 1, @workspace.billing.limit(:press_kits).used
  end

  test "moving a press kit into a full workspace is blocked" do
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    RecordingStudioStripe::ApplySubscription.call(root_recording: @root, price: starter)
    3.times { |index| record_press_kit!("Kit #{index + 1}") }

    other = Workspace.create!(name: "Other Studio #{SecureRandom.hex(4)}")
    other_root = RecordingStudio.root_recording_for(other)
    grant_owner_access!(recording: other_root, actor: @user)
    RecordingStudioStripe::ApplySubscription.call(root_recording: other_root, price: starter)
    moving = other_root.record(PressKit) { |kit| kit.name = "Traveler" }

    error = assert_raises(RecordingStudioStripe::PlanLimitReached) do
      moving.update!(parent_recording_id: @root.id, root_recording_id: @root.id)
    end
    assert_includes error.user_message, "press kits"
    assert_equal other_root.id, moving.reload.root_recording_id
  end

  private

  def record_press_kit!(name)
    @root.record(PressKit) { |kit| kit.name = name }
  end
end
