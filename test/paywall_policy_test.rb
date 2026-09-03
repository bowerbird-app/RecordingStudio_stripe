# frozen_string_literal: true

require "test_helper"

class PaywallPolicyTest < Minitest::Test
  def test_fails_closed_without_accessible
    refute RecordingStudioStripe::PaywallPolicy.allowed?(
      actor: Object.new,
      recording: Object.new,
      paywall_name: "generate_image"
    )
  end

  def test_fails_closed_when_actor_or_recording_is_blank
    refute RecordingStudioStripe::PaywallPolicy.allowed?(
      actor: nil,
      recording: Object.new,
      paywall_name: "generate_image"
    )
    refute RecordingStudioStripe::PaywallPolicy.allowed?(
      actor: Object.new,
      recording: nil,
      paywall_name: "generate_image"
    )
    refute RecordingStudioStripe::PaywallPolicy.allowed?(
      actor: Object.new,
      recording: Object.new,
      paywall_name: ""
    )
  end

  def test_register_paywall_actions_is_a_noop_without_accessible
    assert_nil RecordingStudioStripe::RegisterPaywallActions.call
  end
end
