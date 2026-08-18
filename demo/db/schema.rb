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

ActiveRecord::Schema[8.2].define(version: 2026_08_18_230000) do
  create_table "damage_reports", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.integer "equipment_id"
    t.text "description"
    t.boolean "approved"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "custom_fields", default: {}, null: false
    t.string "state"
    t.index ["tenant_id"], name: "index_damage_reports_on_tenant_id"
  end

  create_table "equipment", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.string "name"
    t.decimal "daily_rate"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "custom_fields", default: {}, null: false
    t.index ["tenant_id"], name: "index_equipment_on_tenant_id"
  end

  create_table "loam_audit_records", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.string "auditable_type", null: false
    t.bigint "auditable_id", null: false
    t.string "action", null: false
    t.bigint "actor_id"
    t.text "changeset"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "auditable_type", "auditable_id"], name: "idx_on_tenant_id_auditable_type_auditable_id_3d28ce6bd5"
    t.index ["tenant_id"], name: "index_loam_audit_records_on_tenant_id"
  end

  create_table "loam_field_definitions", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.string "entity_type", null: false
    t.string "name", null: false
    t.string "field_type", null: false
    t.json "writable_roles", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "entity_type", "name"], name: "index_loam_field_definitions_on_tenant_entity_name", unique: true
    t.index ["tenant_id"], name: "index_loam_field_definitions_on_tenant_id"
  end

  create_table "loam_memberships", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.integer "user_id", null: false
    t.string "role", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "user_id"], name: "index_loam_memberships_on_tenant_id_and_user_id", unique: true
    t.index ["tenant_id"], name: "index_loam_memberships_on_tenant_id"
    t.index ["user_id"], name: "index_loam_memberships_on_user_id"
  end

  create_table "loam_notifications", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.integer "user_id", null: false
    t.string "title", null: false
    t.text "body"
    t.datetime "read_at"
    t.string "source_type"
    t.bigint "source_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "user_id", "read_at"], name: "index_loam_notifications_on_tenant_id_and_user_id_and_read_at"
    t.index ["tenant_id"], name: "index_loam_notifications_on_tenant_id"
    t.index ["user_id"], name: "index_loam_notifications_on_user_id"
  end

  create_table "loam_tenants", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_loam_tenants_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "damage_reports", "loam_tenants", column: "tenant_id"
  add_foreign_key "equipment", "loam_tenants", column: "tenant_id"
  add_foreign_key "loam_audit_records", "loam_tenants", column: "tenant_id"
  add_foreign_key "loam_field_definitions", "loam_tenants", column: "tenant_id"
  add_foreign_key "loam_memberships", "loam_tenants", column: "tenant_id"
  add_foreign_key "loam_memberships", "users"
  add_foreign_key "loam_notifications", "loam_tenants", column: "tenant_id"
  add_foreign_key "loam_notifications", "users"
end
