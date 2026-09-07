# frozen_string_literal: true

class HardenStripeBilling < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_stripe_usage_entries, :subscription_type, :string
    add_column :recording_studio_stripe_allowance_purchases, :subscription_type, :string

    add_index :recording_studio_stripe_usage_entries,
              %i[root_recording_id subscription_type meter_id],
              name: "idx_rs_stripe_usage_root_type_meter"

    remove_index :recording_studio_stripe_usage_entries,
                 name: "index_recording_studio_stripe_usage_entries_on_idempotency_key"
    add_index :recording_studio_stripe_usage_entries,
              %i[root_recording_id idempotency_key],
              unique: true,
              where: "idempotency_key IS NOT NULL",
              name: "idx_rs_stripe_usages_root_idempotency"
  end
end
