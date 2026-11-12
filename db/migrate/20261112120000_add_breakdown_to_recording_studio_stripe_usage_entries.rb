# frozen_string_literal: true

class AddBreakdownToRecordingStudioStripeUsageEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_stripe_usage_entries, :breakdown, :jsonb
  end
end
