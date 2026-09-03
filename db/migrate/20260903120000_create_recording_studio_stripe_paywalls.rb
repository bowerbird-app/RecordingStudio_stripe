# frozen_string_literal: true

class CreateRecordingStudioStripePaywalls < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_stripe_paywalls, id: :uuid do |t|
      t.string :name, null: false
      t.string :label, null: false
      t.timestamps
    end
    add_index :recording_studio_stripe_paywalls, :name, unique: true

    create_table :recording_studio_stripe_product_paywalls, id: :uuid do |t|
      t.references :product, null: false, type: :uuid,
                             foreign_key: { to_table: :recording_studio_stripe_products }
      t.references :paywall, null: false, type: :uuid,
                             foreign_key: { to_table: :recording_studio_stripe_paywalls }
      t.timestamps
    end
    add_index :recording_studio_stripe_product_paywalls, %i[product_id paywall_id],
              unique: true, name: "idx_rs_stripe_product_paywalls_unique"
  end
end
