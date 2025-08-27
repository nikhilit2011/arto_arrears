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

ActiveRecord::Schema[7.1].define(version: 2025_08_25_181212) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "arrear_cases", force: :cascade do |t|
    t.string "vehicle_number"
    t.string "normalized_vehicle_number"
    t.string "vehicle_type"
    t.date "tax_arrear_from"
    t.date "first_notice_date"
    t.bigint "first_notice_tax_cents"
    t.bigint "first_notice_penalty_cents"
    t.bigint "first_notice_total_cents"
    t.date "second_notice_date"
    t.bigint "second_notice_tax_cents"
    t.bigint "second_notice_penalty_cents"
    t.bigint "second_notice_total_cents"
    t.date "recovery_challan_date"
    t.bigint "recovery_challan_tax_cents"
    t.bigint "recovery_challan_penalty_cents"
    t.boolean "tax_paid_status"
    t.date "tax_paid_date"
    t.bigint "tax_paid_amount_cents"
    t.text "remarks"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["normalized_vehicle_number"], name: "index_arrear_cases_on_normalized_vehicle_number"
  end

  create_table "tax_payments", force: :cascade do |t|
    t.string "vehicle_number"
    t.string "normalized_vehicle_number"
    t.date "payment_date"
    t.bigint "amount_cents"
    t.string "payment_ref"
    t.string "source_file"
    t.boolean "matched"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["normalized_vehicle_number"], name: "index_tax_payments_on_normalized_vehicle_number"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "role"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

end
