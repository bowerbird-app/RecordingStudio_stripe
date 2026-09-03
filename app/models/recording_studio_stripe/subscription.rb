# frozen_string_literal: true

module RecordingStudioStripe
  class Subscription < ApplicationRecord
    self.table_name = "recording_studio_stripe_subscriptions"

    ACTIVE_STATUSES = %w[active trialing past_due].freeze

    belongs_to :customer, class_name: "RecordingStudioStripe::Customer"
    belongs_to :price, class_name: "RecordingStudioStripe::Price", optional: true
    belongs_to :scheduled_price, class_name: "RecordingStudioStripe::Price", optional: true

    validates :stripe_id, presence: true, uniqueness: true
    validates :root_recording_id, presence: true
    validates :status, presence: true
    validates :subscription_type, presence: true

    before_validation :assign_default_subscription_type

    scope :current, -> { where(status: ACTIVE_STATUSES) }

    def self.current_for(root_recording_id:, subscription_type: nil)
      scope = current.where(root_recording_id: root_recording_id)
      scope = scope.where(subscription_type: subscription_type.to_s) if subscription_type.present?
      scope.order(updated_at: :desc).first
    end

    def active?
      ACTIVE_STATUSES.include?(status)
    end

    def canceling?
      cancel_at_period_end?
    end

    def scheduled_downgrade?
      scheduled_price_id.present? && scheduled_price_id != price_id
    end

    def subscription_type_label
      SubscriptionTypes.label(subscription_type)
    end

    private

    def assign_default_subscription_type
      self.subscription_type = subscription_type.presence || SubscriptionTypes.keys.first
    end
  end
end
