# frozen_string_literal: true

require "test_helper"

class BillingRootTest < ActiveSupport::TestCase
  setup do
    @user = User.find_or_create_by!(email: "billing-root@example.com") do |user|
      user.password = "Password123!"
      user.password_confirmation = "Password123!"
    end
    Current.actor = @user
  end

  teardown do
    Current.actor = nil
  end

  test "billing creates a missing workspace root once" do
    workspace = Workspace.create!(name: "Billing root #{SecureRandom.hex(4)}")

    assert_nil RecordingStudio.root_recording_for(workspace)

    billing = nil
    assert_difference -> { RecordingStudio::Event.count }, 1 do
      billing = workspace.billing
    end

    root = billing.root_recording
    assert_equal workspace, root.recordable
    assert_equal 1, root.events.where(action: "created").count

    assert_no_difference -> { RecordingStudio::Event.count } do
      assert_equal root, workspace.billing.root_recording
      assert_equal root, RecordingStudio.create_root_recording!(workspace, actor: @user)
    end
    assert_equal root, RecordingStudio.root_recording_for(workspace)
  end

  test "site admin lookup does not create a root" do
    admin_root = AdminRoot.create!(name: "Lookup #{SecureRandom.hex(4)}")

    assert_nil RecordingStudio.root_recording_for(admin_root)
    assert_nil RecordingStudioStripe::SiteAdminRecording.recording_from(admin_root)
    assert_equal 0, RecordingStudio::Recording.where(recordable: admin_root).count
  end
end
