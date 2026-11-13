# frozen_string_literal: true

require "test_helper"

class PlanLimitGuardTest < ActiveSupport::TestCase
  test "Recording includes the plan limit guard through the stripe capability" do
    RecordingStudio.apply_capabilities!

    recording = RecordingStudio::Recording
    registration = RecordingStudio.registered_capabilities.fetch(:stripe)

    assert_equal RecordingStudioStripe::RecordingBilling, registration.fetch(:recording_methods)
    assert_includes recording.included_modules, RecordingStudioStripe::RecordingBilling
    assert_includes recording.included_modules, RecordingStudioStripe::PlanLimitGuard
    assert recording.private_method_defined?(:recording_studio_stripe_enforce_plan_limit)
    assert_nil find_initializer("recording_studio_stripe.plan_limits")

    create_filters = before_filters(recording, :_create_callbacks)
    root_at = create_filters.index(:assign_root_recording_id)
    guard_at = create_filters.index(:recording_studio_stripe_enforce_plan_limit)
    assert root_at
    assert guard_at
    assert_operator root_at, :<, guard_at
    assert_equal 1, create_filters.count(:recording_studio_stripe_enforce_plan_limit)

    update_filters = before_filters(recording, :_update_callbacks)
    assert_equal 1, update_filters.count(:recording_studio_stripe_enforce_plan_limit_on_restore)
    assert_equal 1, update_filters.count(:recording_studio_stripe_enforce_plan_limit_on_move)
  end

  private

  def before_filters(model, chain_name)
    model.public_send(chain_name).filter_map do |callback|
      next unless callback.kind == :before

      filter = callback.filter
      filter.is_a?(String) ? filter.to_sym : filter
    end
  end

  def find_initializer(name)
    RecordingStudioStripe::Engine.initializers.find { |initializer| initializer.name == name }
  end
end
