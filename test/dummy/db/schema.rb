# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_03_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "admin_roots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "folders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "pages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "recording_studio_accesses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_id", null: false
    t.string "actor_type", null: false
    t.datetime "created_at", null: false
    t.integer "role", default: 0, null: false
    t.index ["actor_type", "actor_id", "role"], name: "index_recording_studio_accesses_on_actor_and_role"
    t.index ["actor_type", "actor_id"], name: "index_recording_studio_accesses_on_actor"
  end

  create_table "recording_studio_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.uuid "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "idempotency_key"
    t.uuid "impersonator_id"
    t.string "impersonator_type"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "previous_recordable_id"
    t.string "previous_recordable_type"
    t.uuid "recordable_id", null: false
    t.string "recordable_type", null: false
    t.uuid "recording_id", null: false
    t.index ["action", "occurred_at"], name: "index_rs_events_on_action_and_occurred_at"
    t.index ["actor_type", "actor_id", "occurred_at"], name: "index_rs_events_on_actor_and_occurred_at"
    t.index ["recording_id", "idempotency_key"], name: "index_recording_studio_events_on_recording_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["recording_id", "occurred_at", "created_at"], name: "index_rs_events_on_recording_and_timeline", order: { occurred_at: :desc, created_at: :desc }
    t.index ["recording_id"], name: "index_recording_studio_events_on_recording_id"
  end

  create_table "recording_studio_recordings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "parent_recording_id"
    t.uuid "recordable_id", null: false
    t.string "recordable_type", null: false
    t.uuid "root_recording_id"
    t.datetime "trashed_at"
    t.datetime "updated_at", null: false
    t.index ["parent_recording_id"], name: "index_recording_studio_recordings_on_parent_recording_id"
    t.index ["recordable_type", "recordable_id", "parent_recording_id", "trashed_at"], name: "index_recording_studio_recordings_on_recordable_parent_trashed"
    t.index ["recordable_type", "recordable_id"], name: "index_recording_studio_recordings_on_recordable"
    t.index ["recordable_type", "recordable_id"], name: "index_rs_unique_root_recording_per_recordable", unique: true, where: "(parent_recording_id IS NULL)"
    t.index ["root_recording_id", "parent_recording_id"], name: "index_rs_recordings_on_root_and_parent"
    t.index ["root_recording_id", "recordable_type", "recordable_id"], name: "index_rs_recordings_on_root_and_recordable"
    t.index ["root_recording_id"], name: "index_rs_recordings_on_root_recording"
  end

  create_table "recording_studio_root_switchable_selections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "device_browser"
    t.string "device_key", null: false
    t.string "device_label"
    t.string "device_platform"
    t.string "device_type"
    t.datetime "last_used_at", null: false
    t.uuid "root_recording_id", null: false
    t.string "scope_key", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["actor_type", "actor_id", "device_key", "scope_key"], name: "idx_rs_root_switchable_actor_device_scope", unique: true, where: "(actor_id IS NOT NULL)"
    t.index ["device_key", "scope_key"], name: "idx_rs_root_switchable_anonymous_device_scope", unique: true, where: "(actor_id IS NULL)"
    t.index ["root_recording_id"], name: "idx_rs_root_switchable_root_recording"
  end

  create_table "recording_studio_stripe_allowance_purchases", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "customer_id"
    t.uuid "meter_id", null: false
    t.uuid "price_id"
    t.datetime "purchased_at", null: false
    t.bigint "quantity", null: false
    t.uuid "root_recording_id", null: false
    t.string "stripe_checkout_session_id"
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "idx_on_customer_id_100eab8f3f"
    t.index ["meter_id"], name: "index_recording_studio_stripe_allowance_purchases_on_meter_id"
    t.index ["price_id"], name: "index_recording_studio_stripe_allowance_purchases_on_price_id"
    t.index ["root_recording_id", "meter_id", "purchased_at"], name: "idx_rs_stripe_allowance_root_meter_purchased"
    t.index ["stripe_checkout_session_id"], name: "idx_on_stripe_checkout_session_id_1cb51a2418", unique: true, where: "(stripe_checkout_session_id IS NOT NULL)"
  end

  create_table "recording_studio_stripe_customers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.uuid "root_recording_id", null: false
    t.string "stripe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["root_recording_id"], name: "index_recording_studio_stripe_customers_on_root_recording_id", unique: true
    t.index ["stripe_id"], name: "index_recording_studio_stripe_customers_on_stripe_id", unique: true
  end

  create_table "recording_studio_stripe_meters", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "label", null: false
    t.string "name", null: false
    t.string "stripe_meter_id"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_recording_studio_stripe_meters_on_name", unique: true
  end

  create_table "recording_studio_stripe_paywalls", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "label", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_recording_studio_stripe_paywalls_on_name", unique: true
  end

  create_table "recording_studio_stripe_prices", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "usd", null: false
    t.string "interval"
    t.jsonb "metadata", default: {}, null: false
    t.uuid "product_id", null: false
    t.string "stripe_id", null: false
    t.integer "unit_amount", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id", "interval"], name: "idx_on_product_id_interval_239437eeae"
    t.index ["product_id"], name: "index_recording_studio_stripe_prices_on_product_id"
    t.index ["stripe_id"], name: "index_recording_studio_stripe_prices_on_stripe_id", unique: true
  end

  create_table "recording_studio_stripe_product_paywalls", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "paywall_id", null: false
    t.uuid "product_id", null: false
    t.datetime "updated_at", null: false
    t.index ["paywall_id"], name: "index_recording_studio_stripe_product_paywalls_on_paywall_id"
    t.index ["product_id", "paywall_id"], name: "idx_rs_stripe_product_paywalls_unique", unique: true
    t.index ["product_id"], name: "index_recording_studio_stripe_product_paywalls_on_product_id"
  end

  create_table "recording_studio_stripe_products", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.string "kind", default: "plan", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "stripe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["kind", "active"], name: "index_recording_studio_stripe_products_on_kind_and_active"
    t.index ["stripe_id"], name: "index_recording_studio_stripe_products_on_stripe_id", unique: true
  end

  create_table "recording_studio_stripe_subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "cancel_at_period_end", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "current_period_end"
    t.datetime "current_period_start"
    t.uuid "customer_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "price_id"
    t.uuid "root_recording_id", null: false
    t.uuid "scheduled_price_id"
    t.string "status", null: false
    t.string "stripe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_recording_studio_stripe_subscriptions_on_customer_id"
    t.index ["price_id"], name: "index_recording_studio_stripe_subscriptions_on_price_id"
    t.index ["root_recording_id", "status"], name: "idx_on_root_recording_id_status_0c1c783865"
    t.index ["scheduled_price_id"], name: "idx_on_scheduled_price_id_2cf55663e2"
    t.index ["stripe_id"], name: "index_recording_studio_stripe_subscriptions_on_stripe_id", unique: true
  end

  create_table "recording_studio_stripe_usage_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "idempotency_key"
    t.uuid "meter_id", null: false
    t.bigint "quantity", null: false
    t.datetime "recorded_at", null: false
    t.uuid "root_recording_id", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_recording_studio_stripe_usage_entries_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["meter_id"], name: "index_recording_studio_stripe_usage_entries_on_meter_id"
    t.index ["root_recording_id", "meter_id", "recorded_at"], name: "idx_rs_stripe_usage_root_meter_recorded"
  end

  create_table "recording_studio_stripe_webhook_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "processed_at", null: false
    t.string "stripe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["stripe_id"], name: "index_recording_studio_stripe_webhook_events_on_stripe_id", unique: true
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "workspaces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "recording_studio_events", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "parent_recording_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "root_recording_id"
  add_foreign_key "recording_studio_stripe_allowance_purchases", "recording_studio_stripe_customers", column: "customer_id"
  add_foreign_key "recording_studio_stripe_allowance_purchases", "recording_studio_stripe_meters", column: "meter_id"
  add_foreign_key "recording_studio_stripe_allowance_purchases", "recording_studio_stripe_prices", column: "price_id"
  add_foreign_key "recording_studio_stripe_prices", "recording_studio_stripe_products", column: "product_id"
  add_foreign_key "recording_studio_stripe_product_paywalls", "recording_studio_stripe_paywalls", column: "paywall_id"
  add_foreign_key "recording_studio_stripe_product_paywalls", "recording_studio_stripe_products", column: "product_id"
  add_foreign_key "recording_studio_stripe_subscriptions", "recording_studio_stripe_customers", column: "customer_id"
  add_foreign_key "recording_studio_stripe_subscriptions", "recording_studio_stripe_prices", column: "price_id"
  add_foreign_key "recording_studio_stripe_subscriptions", "recording_studio_stripe_prices", column: "scheduled_price_id"
  add_foreign_key "recording_studio_stripe_usage_entries", "recording_studio_stripe_meters", column: "meter_id"
end
