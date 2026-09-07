# frozen_string_literal: true

module RecordingStudioStripe
  module PlanLimitGuard
    extend ActiveSupport::Concern

    included do
      before_create :recording_studio_stripe_enforce_plan_limit
      before_update :recording_studio_stripe_enforce_plan_limit_on_restore
      before_update :recording_studio_stripe_enforce_plan_limit_on_move
    end

    private

    def recording_studio_stripe_enforce_plan_limit
      return unless Limits.configured?
      return unless Limits.covers_type?(recordable_type)
      return unless recording_studio_stripe_billable_root?

      root = recording_studio_stripe_limit_root
      return unless root

      AdvisoryLock.hold(self.class.connection, "#{root.id}:#{recordable_type}")
      Limits.for_recordable_type(recordable_type).each do |definition|
        handle = LimitHandle.new(
          root_recording: root,
          name: definition.name,
          subscription_type: definition.subscription_type
        )
        next if handle.available?(1)

        raise PlanLimitReached.new(handle: handle)
      end
    end

    def recording_studio_stripe_enforce_plan_limit_on_restore
      return unless self.class.column_names.include?("trashed_at")
      return unless will_save_change_to_trashed_at?
      return unless trashed_at.nil?
      return if trashed_at_in_database.nil?

      recording_studio_stripe_enforce_plan_limit
    end

    def recording_studio_stripe_enforce_plan_limit_on_move
      return unless recording_studio_stripe_parent_or_root_changing?

      recording_studio_stripe_enforce_plan_limit
    end

    def recording_studio_stripe_parent_or_root_changing?
      changing = false
      changing ||= will_save_change_to_parent_recording_id? if respond_to?(:will_save_change_to_parent_recording_id?)
      if self.class.column_names.include?("root_recording_id") && respond_to?(:will_save_change_to_root_recording_id?)
        changing ||= will_save_change_to_root_recording_id?
      end
      changing
    end

    def recording_studio_stripe_billable_root?
      root = recording_studio_stripe_limit_root
      return false unless root

      recordable = root.try(:recordable)
      return false unless recordable
      return false unless defined?(RecordingStudio)

      RecordingStudio.capability_enabled?(:stripe, for: recordable.class)
    end

    def recording_studio_stripe_limit_root
      return root_recording if root_recording.present?
      return self.class.find_by(id: root_recording_id) if root_recording_id.present?
      return parent_recording.root_recording || parent_recording if parent_recording

      self.class.find_by(id: parent_recording_id)
    end
  end
end
