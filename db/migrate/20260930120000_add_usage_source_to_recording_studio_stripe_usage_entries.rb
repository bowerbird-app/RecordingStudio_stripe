# frozen_string_literal: true

class AddUsageSourceToRecordingStudioStripeUsageEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_stripe_usage_entries, :usage_key, :string
    add_column :recording_studio_stripe_usage_entries, :source_quantity, :integer
    add_column :recording_studio_stripe_usage_entries, :credit_rate, :integer
  end
end
