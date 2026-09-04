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

ActiveRecord::Schema[8.1].define(version: 2026_09_04_192650) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.integer "avg_daily_burn", default: 0, null: false
    t.string "billing_contact"
    t.string "company_name", null: false
    t.datetime "created_at", null: false
    t.integer "credits_used_this_cycle", default: 0, null: false
    t.date "cycle_end"
    t.date "cycle_start"
    t.jsonb "enabled_modules", default: [], null: false
    t.string "external_id", null: false
    t.integer "monthly_credit_allowance", default: 0, null: false
    t.string "plan", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_accounts_on_external_id", unique: true
  end

  create_table "activity_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.bigint "lead_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["lead_id", "id"], name: "index_activity_events_on_lead_id_and_id"
    t.index ["lead_id"], name: "index_activity_events_on_lead_id"
  end

  create_table "credit_transactions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.string "layer_name", null: false
    t.string "transaction_type", default: "verification", null: false
    t.datetime "updated_at", null: false
    t.bigint "verification_run_id", null: false
    t.index ["account_id"], name: "index_credit_transactions_on_account_id"
    t.index ["verification_run_id", "layer_name"], name: "idx_on_verification_run_id_layer_name_e2039dbf06", unique: true
    t.index ["verification_run_id"], name: "index_credit_transactions_on_verification_run_id"
  end

  create_table "layer_results", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "credit_cost", default: 0, null: false
    t.string "execution_status", default: "pending", null: false
    t.string "layer_name", null: false
    t.jsonb "raw_response", default: {}, null: false
    t.text "reason"
    t.integer "risk_score", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "verdict"
    t.bigint "verification_run_id", null: false
    t.index ["verification_run_id", "layer_name"], name: "index_layer_results_on_verification_run_id_and_layer_name", unique: true
    t.index ["verification_run_id"], name: "index_layer_results_on_verification_run_id"
  end

  create_table "leads", force: :cascade do |t|
    t.string "campaign"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "external_id", null: false
    t.string "first_name"
    t.integer "form_dwell_ms"
    t.text "landing_page_url", null: false
    t.string "last_name"
    t.string "phone"
    t.bigint "pixel_session_id", null: false
    t.string "submit_ip"
    t.datetime "submitted_at", null: false
    t.text "trusted_form_cert_url"
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["external_id"], name: "index_leads_on_external_id", unique: true
    t.index ["pixel_session_id"], name: "index_leads_on_pixel_session_id", unique: true
  end

  create_table "pixel_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "page_url", null: false
    t.bigint "pixel_id", null: false
    t.text "referrer"
    t.string "session_id", null: false
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.string "visit_ip"
    t.index ["pixel_id"], name: "index_pixel_sessions_on_pixel_id"
    t.index ["session_id"], name: "index_pixel_sessions_on_session_id", unique: true
  end

  create_table "pixels", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.boolean "active", default: true, null: false
    t.jsonb "allowed_pages", default: [], null: false
    t.datetime "created_at", null: false
    t.jsonb "enabled_modules", default: [], null: false
    t.string "name", null: false
    t.string "public_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_pixels_on_account_id"
    t.index ["public_id"], name: "index_pixels_on_public_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.bigint "account_id"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "external_id", null: false
    t.string "name", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["external_id"], name: "index_users_on_external_id", unique: true
  end

  create_table "verdicts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "decided_at", null: false
    t.string "decision", null: false
    t.boolean "hard_stop", default: false, null: false
    t.jsonb "policy_snapshot", default: {}, null: false
    t.jsonb "reasons", default: [], null: false
    t.integer "risk_score", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "verification_run_id", null: false
    t.index ["verification_run_id"], name: "index_verdicts_on_verification_run_id", unique: true
  end

  create_table "verification_runs", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "lead_id", null: false
    t.string "policy_version", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["lead_id", "created_at"], name: "index_verification_runs_on_lead_id_and_created_at"
    t.index ["lead_id"], name: "index_verification_runs_on_lead_id"
  end

  add_foreign_key "activity_events", "leads"
  add_foreign_key "credit_transactions", "accounts"
  add_foreign_key "credit_transactions", "verification_runs"
  add_foreign_key "layer_results", "verification_runs"
  add_foreign_key "leads", "pixel_sessions"
  add_foreign_key "pixel_sessions", "pixels"
  add_foreign_key "pixels", "accounts"
  add_foreign_key "users", "accounts"
  add_foreign_key "verdicts", "verification_runs"
  add_foreign_key "verification_runs", "leads"
end
