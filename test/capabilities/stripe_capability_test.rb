# frozen_string_literal: true

require "test_helper"

class StripeCapabilityTest < Minitest::Test
  def test_stripe_capability_is_registered
    assert RecordingStudio.registered_capabilities.key?(:stripe)
    assert_equal "RecordingStudioStripe::Billable",
                 RecordingStudio.registered_capabilities[:stripe][:source]
  end

  def test_installing_the_gem_does_not_enable_stripe_on_arbitrary_types
    refute RecordingStudio.capability_enabled?(:stripe, for: "Folder")
    refute RecordingStudio.capability_enabled?(:stripe, for: "Page")
  end
end
