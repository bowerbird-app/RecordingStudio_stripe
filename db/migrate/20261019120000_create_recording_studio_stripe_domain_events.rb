# frozen_string_literal: true

class CreateRecordingStudioStripeDomainEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_stripe_domain_events, id: :uuid do |t|
      t.string :name, null: false
      t.string :idempotency_key, null: false
      t.uuid :subscription_id, null: false
      t.uuid :customer_id, null: false
      t.uuid :root_recording_id, null: false
      t.uuid :webhook_event_id
      t.jsonb :payload, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :published_at
      t.datetime :publish_claimed_at
      t.integer :publish_attempts, null: false, default: 0
      t.timestamps
    end

    add_index :recording_studio_stripe_domain_events, :idempotency_key,
              unique: true,
              name: "idx_rs_stripe_domain_events_idempotency"
    add_index :recording_studio_stripe_domain_events, :webhook_event_id,
              name: "idx_rs_stripe_domain_events_webhook"
    add_index :recording_studio_stripe_domain_events, %i[subscription_id name],
              name: "idx_rs_stripe_domain_events_sub_name"
    add_index :recording_studio_stripe_domain_events, :customer_id,
              name: "idx_rs_stripe_domain_events_customer"
    add_index :recording_studio_stripe_domain_events, :created_at,
              where: "published_at IS NULL",
              name: "idx_rs_stripe_domain_events_unpublished"

    add_foreign_key :recording_studio_stripe_domain_events,
                    :recording_studio_stripe_subscriptions,
                    column: :subscription_id,
                    on_delete: :cascade
    add_foreign_key :recording_studio_stripe_domain_events,
                    :recording_studio_stripe_customers,
                    column: :customer_id,
                    on_delete: :cascade
    add_foreign_key :recording_studio_stripe_domain_events,
                    :recording_studio_stripe_webhook_events,
                    column: :webhook_event_id

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE recording_studio_stripe_subscriptions
          SET metadata = metadata || '{"payments_tracked": true}'::jsonb
          WHERE status IN ('trialing', 'incomplete')
        SQL
      end
    end
  end
end
