# frozen_string_literal: true

module RecordingStudioStripe
  class Customer < ApplicationRecord
    self.table_name = "recording_studio_stripe_customers"

    has_many :subscriptions, class_name: "RecordingStudioStripe::Subscription", dependent: :destroy
    has_many :allowance_purchases, class_name: "RecordingStudioStripe::AllowancePurchase", dependent: :delete_all

    validates :root_recording_id, presence: true, uniqueness: true
    validates :stripe_id, presence: true, uniqueness: true

    def root_recording
      RecordingStudio::Recording.find_by(id: root_recording_id)
    end
  end
end
