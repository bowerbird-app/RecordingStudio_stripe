# frozen_string_literal: true

module RecordingStudioStripe
  class LimitHandle
    attr_reader :root_recording, :name, :subscription_type

    def initialize(root_recording:, name:, subscription_type: nil)
      @root_recording = root_recording
      @definition = Limits.fetch(name)
      @name = @definition.name
      @subscription_type = subscription_type.presence || @definition.subscription_type
    end

    def label
      @definition.label
    end

    def recordable_type
      @definition.recordable_type
    end

    def included
      product = self.product
      return 0 unless product&.plan?

      product.limit_quantity(name)
    end

    def used
      return 0 if root_recording.blank?

      live_recordings.count
    end

    def remaining
      [included - used, 0].max
    end

    def available?(quantity = 1)
      remaining >= quantity.to_i
    end

    def over?
      used > included
    end

    def product
      subscription&.price&.product
    end

    def subscription
      return if root_recording.blank?

      @subscription ||= Subscription.current_for(
        root_recording_id: root_recording.id,
        subscription_type: subscription_type
      )
    end

    private

    def live_recordings
      scope = RecordingStudio::Recording.for_root(root_recording.id).of_type(recordable_type)
      return scope unless RecordingStudio::Recording.column_names.include?("trashed_at")

      scope.where(trashed_at: nil)
    end
  end
end
