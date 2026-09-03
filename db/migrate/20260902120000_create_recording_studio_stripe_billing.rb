# frozen_string_literal: true

class CreateRecordingStudioStripeBilling < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_stripe_meters, id: :uuid do |t|
      t.string :name, null: false
      t.string :label, null: false
      t.string :stripe_meter_id
      t.timestamps
    end
    add_index :recording_studio_stripe_meters, :name, unique: true

    create_table :recording_studio_stripe_products, id: :uuid do |t|
      t.string :stripe_id, null: false
      t.string :name, null: false
      t.string :description
      t.string :kind, null: false, default: "plan"
      t.boolean :active, null: false, default: true
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :recording_studio_stripe_products, :stripe_id, unique: true
    add_index :recording_studio_stripe_products, %i[kind active]

    create_table :recording_studio_stripe_prices, id: :uuid do |t|
      t.string :stripe_id, null: false
      t.references :product, null: false, type: :uuid, foreign_key: { to_table: :recording_studio_stripe_products }
      t.integer :unit_amount, null: false
      t.string :currency, null: false, default: "usd"
      t.string :interval
      t.boolean :active, null: false, default: true
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :recording_studio_stripe_prices, :stripe_id, unique: true
    add_index :recording_studio_stripe_prices, %i[product_id interval]

    create_table :recording_studio_stripe_customers, id: :uuid do |t|
      t.uuid :root_recording_id, null: false
      t.string :stripe_id, null: false
      t.string :email
      t.timestamps
    end
    add_index :recording_studio_stripe_customers, :root_recording_id, unique: true
    add_index :recording_studio_stripe_customers, :stripe_id, unique: true

    create_table :recording_studio_stripe_subscriptions, id: :uuid do |t|
      t.string :stripe_id, null: false
      t.uuid :root_recording_id, null: false
      t.references :customer, null: false, type: :uuid, foreign_key: { to_table: :recording_studio_stripe_customers }
      t.references :price, type: :uuid, foreign_key: { to_table: :recording_studio_stripe_prices }
      t.references :scheduled_price, type: :uuid, foreign_key: { to_table: :recording_studio_stripe_prices }
      t.string :status, null: false
      t.boolean :cancel_at_period_end, null: false, default: false
      t.datetime :current_period_start
      t.datetime :current_period_end
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :recording_studio_stripe_subscriptions, :stripe_id, unique: true
    add_index :recording_studio_stripe_subscriptions, %i[root_recording_id status]

    create_table :recording_studio_stripe_usage_entries, id: :uuid do |t|
      t.uuid :root_recording_id, null: false
      t.references :meter, null: false, type: :uuid, foreign_key: { to_table: :recording_studio_stripe_meters }
      t.bigint :quantity, null: false
      t.datetime :recorded_at, null: false
      t.string :idempotency_key
      t.timestamps
    end
    add_index :recording_studio_stripe_usage_entries, %i[root_recording_id meter_id recorded_at],
              name: "idx_rs_stripe_usage_root_meter_recorded"
    add_index :recording_studio_stripe_usage_entries, :idempotency_key, unique: true,
                                                                        where: "idempotency_key IS NOT NULL"

    create_table :recording_studio_stripe_allowance_purchases, id: :uuid do |t|
      t.uuid :root_recording_id, null: false
      t.references :meter, null: false, type: :uuid, foreign_key: { to_table: :recording_studio_stripe_meters }
      t.references :customer, type: :uuid, foreign_key: { to_table: :recording_studio_stripe_customers }
      t.references :price, type: :uuid, foreign_key: { to_table: :recording_studio_stripe_prices }
      t.bigint :quantity, null: false
      t.string :stripe_checkout_session_id
      t.datetime :purchased_at, null: false
      t.timestamps
    end
    add_index :recording_studio_stripe_allowance_purchases, %i[root_recording_id meter_id purchased_at],
              name: "idx_rs_stripe_allowance_root_meter_purchased"
    add_index :recording_studio_stripe_allowance_purchases, :stripe_checkout_session_id,
              unique: true, where: "stripe_checkout_session_id IS NOT NULL"

    create_table :recording_studio_stripe_webhook_events, id: :uuid do |t|
      t.string :stripe_id, null: false
      t.string :event_type, null: false
      t.datetime :processed_at, null: false
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end
    add_index :recording_studio_stripe_webhook_events, :stripe_id, unique: true
  end
end
