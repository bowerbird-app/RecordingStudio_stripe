# frozen_string_literal: true

require "test_helper"

class PlanCardSettingsTest < Minitest::Test
  def test_subtitle_is_kept_and_a_blank_one_is_dropped
    settings = RecordingStudioStripe::PlanCardSettings.normalize(
      "subtitle" => "  For small teams  ",
      "hide" => []
    )

    assert_equal "For small teams", settings["subtitle"]
    assert_equal [], settings["hide"]

    cleared = RecordingStudioStripe::PlanCardSettings.normalize("subtitle" => "   ")

    refute cleared.key?("subtitle")
    assert_equal [], cleared["extras"]
  end
end
