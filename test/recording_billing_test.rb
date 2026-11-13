# frozen_string_literal: true

require "test_helper"

class RecordingBillingTest < Minitest::Test
  def test_stripe_capability_installs_plan_limit_callbacks_after_root_assignment
    host = Class.new do
      include ActiveSupport::Callbacks

      define_callbacks :create, :update

      class << self
        def before_create(*filters, **options)
          set_callback(:create, :before, *filters, **options)
        end

        def before_update(*filters, **options)
          set_callback(:update, :before, *filters, **options)
        end
      end

      before_create :assign_root_recording_id
    end

    host.include(RecordingStudioStripe::RecordingBilling)

    assert_includes host.included_modules, RecordingStudioStripe::RecordingBilling
    assert_includes host.included_modules, RecordingStudioStripe::PlanLimitGuard

    create_filters = before_filters(host, :create)
    root_at = create_filters.index(:assign_root_recording_id)
    guard_at = create_filters.index(:recording_studio_stripe_enforce_plan_limit)
    assert root_at
    assert guard_at
    assert_operator root_at, :<, guard_at
    assert_equal 1, create_filters.count(:recording_studio_stripe_enforce_plan_limit)

    update_filters = before_filters(host, :update)
    assert_equal 1, update_filters.count(:recording_studio_stripe_enforce_plan_limit_on_restore)
    assert_equal 1, update_filters.count(:recording_studio_stripe_enforce_plan_limit_on_move)

    registration = RecordingStudio.registered_capabilities.fetch(:stripe)
    assert_equal RecordingStudioStripe::RecordingBilling, registration.fetch(:recording_methods)
    assert_nil find_initializer("recording_studio_stripe.plan_limits")
  end

  private

  def before_filters(host, name)
    host.send(:get_callbacks, name).filter_map do |callback|
      next unless callback.kind == :before

      filter = callback.filter
      filter.is_a?(String) ? filter.to_sym : filter
    end
  end

  def find_initializer(name)
    RecordingStudioStripe::Engine.initializers.find { |initializer| initializer.name == name }
  end
end
