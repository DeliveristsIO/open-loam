class CreateOpenLoamSearchTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :open_loam_search_tokens do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }
      t.string :searchable_type, null: false  # the entity class name (e.g. "Equipment")
      t.bigint :searchable_id, null: false     # the record it indexes
      t.string :token, null: false             # one normalized word
    end
    # The match subquery filters by (tenant, type, token); index maintenance
    # deletes by (tenant, type, record). One index each — no timestamps: these
    # are plumbing rows written with insert_all/delete_all.
    add_index :open_loam_search_tokens, %i[tenant_id searchable_type token]
    add_index :open_loam_search_tokens, %i[tenant_id searchable_type searchable_id]
  end
end
