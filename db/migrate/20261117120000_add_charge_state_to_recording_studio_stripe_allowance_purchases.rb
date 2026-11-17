# frozen_string_literal: true

class AddChargeStateToRecordingStudioStripeAllowancePurchases < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_stripe_allowance_purchases, :stripe_payment_intent_id, :string
    add_column :recording_studio_stripe_allowance_purchases, :status, :string, null: false, default: "active"
    add_column :recording_studio_stripe_allowance_purchases, :credits_frozen, :boolean, null: false, default: false
    add_column :recording_studio_stripe_allowance_purchases, :credits_revoked, :bigint, null: false, default: 0
    add_column :recording_studio_stripe_allowance_purchases, :credit_shortfall, :bigint, null: false, default: 0
    add_column :recording_studio_stripe_allowance_purchases, :refunded_amount, :bigint, null: false, default: 0

    add_index :recording_studio_stripe_allowance_purchases, :stripe_payment_intent_id,
              unique: true,
              where: "stripe_payment_intent_id IS NOT NULL",
              name: "idx_rs_stripe_allowance_payment_intent"
  end
end
