# frozen_string_literal: true

class AddSubscriptionTypeToRecordingStudioStripe < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_stripe_products, :subscription_type, :string, null: false, default: "plan"
    add_column :recording_studio_stripe_subscriptions, :subscription_type, :string, null: false, default: "plan"

    add_index :recording_studio_stripe_products, :subscription_type
    add_index :recording_studio_stripe_subscriptions, %i[root_recording_id subscription_type status],
              name: "idx_rs_stripe_sub_root_type_status"
    add_index :recording_studio_stripe_subscriptions, %i[root_recording_id subscription_type],
              unique: true,
              where: "status IN ('active', 'trialing', 'past_due')",
              name: "idx_rs_stripe_one_live_sub_per_type"
  end
end
