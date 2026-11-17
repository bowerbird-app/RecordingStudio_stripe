# frozen_string_literal: true

require "test_helper"

class CatalogueAccessTest < Minitest::Test
  Request = Struct.new(:verb) do
    def get?
      verb == "GET"
    end

    def head?
      verb == "HEAD"
    end
  end

  def test_reads_use_view_and_other_verbs_use_admin
    assert_equal :view, RecordingStudioStripe::Admin::CatalogueAccess.role_for(Request.new("GET"))
    assert_equal :view, RecordingStudioStripe::Admin::CatalogueAccess.role_for(Request.new("HEAD"))

    %w[POST PUT PATCH DELETE OPTIONS].each do |verb|
      assert_equal :admin, RecordingStudioStripe::Admin::CatalogueAccess.role_for(Request.new(verb))
    end
    assert_equal :admin, RecordingStudioStripe::Admin::CatalogueAccess.role_for(nil)
  end

  def test_allowed_asks_accessible_on_the_site_admin_recording
    actor = Object.new
    controller = Object.new
    recording = Object.new
    calls = []

    RecordingStudioStripe.stub(:site_admin_recording_for, recording) do
      RecordingStudioAccessible.stub(:authorized?, lambda { |**kwargs|
        calls << kwargs
        true
      }) do
        assert RecordingStudioStripe::Admin::CatalogueAccess.allowed?(
          actor: actor, controller: controller, role: :admin
        )
      end
    end

    assert_equal [{ actor: actor, recording: recording, role: :admin }], calls
  end

  def test_allowed_fails_closed_without_a_recording_actor_or_accessible
    actor = Object.new
    recording = Object.new

    RecordingStudioStripe.stub(:site_admin_recording_for, nil) do
      refute RecordingStudioStripe::Admin::CatalogueAccess.allowed?(actor: actor, controller: nil, role: :view)
    end

    RecordingStudioStripe.stub(:site_admin_recording_for, recording) do
      refute RecordingStudioStripe::Admin::CatalogueAccess.allowed?(actor: nil, controller: nil, role: :admin)

      RecordingStudioStripe.stub(:accessible_loaded?, false) do
        refute RecordingStudioStripe::Admin::CatalogueAccess.allowed?(actor: actor, controller: nil, role: :view)
      end
    end
  end

  def test_write_allowed_uses_admin_on_the_screen_context
    actor = Object.new
    controller = Object.new
    context = Struct.new(:current_actor, :controller).new(actor, controller)
    seen = nil

    RecordingStudioStripe::Admin::CatalogueAccess.stub(:allowed?, lambda { |actor:, controller:, role:|
      seen = { actor: actor, controller: controller, role: role }
      true
    }) do
      assert RecordingStudioStripe::Admin::CatalogueAccess.write_allowed?(context)
    end

    assert_equal({ actor: actor, controller: controller, role: :admin }, seen)
  end
end
