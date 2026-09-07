# frozen_string_literal: true

module RecordingStudioStripe
  module LiveSubscription
    module_function

    def find(root_recording:, subscription_type:, missing_type_message:)
      scope = Subscription.current.where(root_recording_id: root_recording.id)
      if subscription_type.present?
        return scope.find_by(subscription_type: SubscriptionTypes.normalize(subscription_type))
      end

      live = scope.order(updated_at: :desc).to_a
      raise NoSubscription, missing_type_message if live.size > 1

      live.first
    end
  end
end
