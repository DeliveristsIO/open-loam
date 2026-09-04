class CreateLoamSearchTokens < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :loam_search_tokens<%= loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }<%= loam_type_option %>
      t.string :searchable_type, null: false  # the entity class name (e.g. "Gadget")
      t.<%= loam_key_column_type %> :searchable_id<%= loam_key_limit_option %>, null: false     # the record it indexes
      t.string :token, null: false             # one normalized word
    end
    # The match subquery filters by (tenant, type, token); index maintenance
    # deletes by (tenant, type, record). One index each — no timestamps: these
    # are plumbing rows written with insert_all/delete_all.
    #
    # Shipped even though the default LikeDriver never uses it, so switching to
    # Loam::Search::TokenDriver is a one-line initializer change, not a migration.
    add_index :loam_search_tokens, %i[tenant_id searchable_type token]
    add_index :loam_search_tokens, %i[tenant_id searchable_type searchable_id]
  end
end
