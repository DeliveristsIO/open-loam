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

ActiveRecord::Schema[8.2].define(version: 2026_08_21_221000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "customers", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.string "name"
    t.text "email"
    t.text "tax_id"
    t.string "email_hash"
    t.json "custom_fields", default: {}, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.index ["deleted_at"], name: "index_customers_on_deleted_at"
    t.index ["email_hash"], name: "index_customers_on_email_hash"
    t.index ["tenant_id"], name: "index_customers_on_tenant_id"
  end

  create_table "damage_reports", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.integer "equipment_id"
    t.text "description"
    t.boolean "approved"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "custom_fields", default: {}, null: false
    t.string "state"
    t.datetime "deleted_at"
    t.integer "lock_version", default: 0, null: false
    t.index ["deleted_at"], name: "index_damage_reports_on_deleted_at"
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
    t.datetime "deleted_at"
    t.integer "lock_version", default: 0, null: false
    t.index ["deleted_at"], name: "index_equipment_on_deleted_at"
    t.index ["tenant_id"], name: "index_equipment_on_tenant_id"
  end

  create_table "loam_api_tokens", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.integer "user_id", null: false
    t.string "token", null: false
    t.string "label"
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id"], name: "index_loam_api_tokens_on_tenant_id"
    t.index ["token"], name: "index_loam_api_tokens_on_token", unique: true
    t.index ["user_id"], name: "index_loam_api_tokens_on_user_id"
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

  create_table "loam_comments", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.string "commentable_type", null: false
    t.bigint "commentable_id", null: false
    t.integer "author_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_loam_comments_on_author_id"
    t.index ["tenant_id", "commentable_type", "commentable_id"], name: "idx_on_tenant_id_commentable_type_commentable_id_038d2261a2"
    t.index ["tenant_id"], name: "index_loam_comments_on_tenant_id"
  end

  create_table "loam_configs", force: :cascade do |t|
    t.string "key", null: false
    t.integer "tenant_id"
    t.json "value_json"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key", "tenant_id"], name: "index_loam_configs_on_key_and_tenant", unique: true
    t.index ["key"], name: "index_loam_configs_global_key", unique: true, where: "tenant_id IS NULL"
    t.index ["tenant_id"], name: "index_loam_configs_on_tenant_id"
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

  create_table "loam_mfa_credentials", force: :cascade do |t|
    t.integer "user_id", null: false
    t.text "totp_secret"
    t.text "recovery_codes"
    t.datetime "activated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "last_totp_step"
    t.index ["user_id"], name: "index_loam_mfa_credentials_on_user_id", unique: true
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

  create_table "loam_pending_actions", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.bigint "actor_id"
    t.string "status", default: "pending", null: false
    t.string "action_type", null: false
    t.string "target_type"
    t.bigint "target_id"
    t.text "changeset"
    t.text "summary", null: false
    t.string "idempotency_key", null: false
    t.bigint "reviewed_by_id"
    t.datetime "reviewed_at"
    t.text "result"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "idempotency_key"], name: "index_loam_pending_actions_pending_key", unique: true, where: "status = 'pending'"
    t.index ["tenant_id", "status"], name: "index_loam_pending_actions_on_tenant_id_and_status"
    t.index ["tenant_id"], name: "index_loam_pending_actions_on_tenant_id"
  end

  create_table "loam_perspectives", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.string "entity_type", null: false
    t.string "name", null: false
    t.bigint "owner_id"
    t.string "visibility", default: "private", null: false
    t.string "role"
    t.boolean "is_default", default: false, null: false
    t.json "config", default: {}, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "entity_type"], name: "index_loam_perspectives_on_tenant_id_and_entity_type"
    t.index ["tenant_id"], name: "index_loam_perspectives_on_tenant_id"
  end

  create_table "loam_record_locks", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.string "lockable_type", null: false
    t.bigint "lockable_id", null: false
    t.integer "locked_by_id", null: false
    t.string "token", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["locked_by_id"], name: "index_loam_record_locks_on_locked_by_id"
    t.index ["tenant_id", "lockable_type", "lockable_id"], name: "index_loam_record_locks_on_lockable", unique: true
    t.index ["tenant_id"], name: "index_loam_record_locks_on_tenant_id"
  end

  create_table "loam_tenants", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_loam_tenants_on_slug", unique: true
  end

  create_table "loam_webhook_endpoints", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.string "url", null: false
    t.string "event_pattern", null: false
    t.string "secret", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "active"], name: "index_loam_webhook_endpoints_on_tenant_id_and_active"
    t.index ["tenant_id"], name: "index_loam_webhook_endpoints_on_tenant_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "password_digest"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "customers", "loam_tenants", column: "tenant_id"
  add_foreign_key "damage_reports", "loam_tenants", column: "tenant_id"
  add_foreign_key "equipment", "loam_tenants", column: "tenant_id"
  add_foreign_key "loam_api_tokens", "loam_tenants", column: "tenant_id"
  add_foreign_key "loam_api_tokens", "users"
  add_foreign_key "loam_audit_records", "loam_tenants", column: "tenant_id"
  add_foreign_key "loam_comments", "loam_tenants", column: "tenant_id"
  add_foreign_key "loam_comments", "users", column: "author_id"
  add_foreign_key "loam_configs", "loam_tenants", column: "tenant_id"
  add_foreign_key "loam_field_definitions", "loam_tenants", column: "tenant_id"
  add_foreign_key "loam_memberships", "loam_tenants", column: "tenant_id"
  add_foreign_key "loam_memberships", "users"
  add_foreign_key "loam_mfa_credentials", "users"
  add_foreign_key "loam_notifications", "loam_tenants", column: "tenant_id"
  add_foreign_key "loam_notifications", "users"
  add_foreign_key "loam_pending_actions", "loam_tenants", column: "tenant_id"
  add_foreign_key "loam_perspectives", "loam_tenants", column: "tenant_id"
  add_foreign_key "loam_record_locks", "loam_tenants", column: "tenant_id"
  add_foreign_key "loam_record_locks", "users", column: "locked_by_id"
  add_foreign_key "loam_webhook_endpoints", "loam_tenants", column: "tenant_id"
end
