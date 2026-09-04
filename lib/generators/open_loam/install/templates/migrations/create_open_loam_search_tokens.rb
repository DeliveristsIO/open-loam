class CreateOpenLoamSearchTokens < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_search_tokens<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.string :searchable_type, null: false  # the entity class name (e.g. "Gadget")
      t.<%= open_loam_key_column_type %> :searchable_id<%= open_loam_key_limit_option %>, null: false     # the record it indexes
      t.string :token, null: false             # one normalized word
    end
    # The match subquery filters by (tenant, type, token); index maintenance
    # deletes by (tenant, type, record). One index each — no timestamps: these
    # are plumbing rows written with insert_all/delete_all.
    #
    # Shipped even though the default LikeDriver never uses it, so switching to
    # OpenLoam::Search::TokenDriver is a one-line initializer change, not a migration.
    add_index :open_loam_search_tokens, %i[tenant_id searchable_type token]
    add_index :open_loam_search_tokens, %i[tenant_id searchable_type searchable_id]
  end
end
