# frozen_string_literal: true

class IndexRecordingStudioStripeDomainEvents < ActiveRecord::Migration[8.1]
  def change
    add_index :recording_studio_stripe_domain_events, :customer_id,
              name: "idx_rs_stripe_domain_events_customer"
    add_index :recording_studio_stripe_domain_events, :created_at,
              where: "published_at IS NULL",
              name: "idx_rs_stripe_domain_events_unpublished"

    remove_foreign_key :recording_studio_stripe_domain_events, :recording_studio_stripe_subscriptions
    remove_foreign_key :recording_studio_stripe_domain_events, :recording_studio_stripe_customers
    add_foreign_key :recording_studio_stripe_domain_events, :recording_studio_stripe_subscriptions,
                    column: :subscription_id, on_delete: :cascade
    add_foreign_key :recording_studio_stripe_domain_events, :recording_studio_stripe_customers,
                    column: :customer_id, on_delete: :cascade
  end
end
