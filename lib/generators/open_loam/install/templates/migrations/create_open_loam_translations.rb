class CreateOpenLoamTranslations < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_translations<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.string :translatable_type, null: false
      t.<%= open_loam_key_column_type %> :translatable_id<%= open_loam_key_limit_option %>, null: false
      t.string :locale, null: false            # "en", "de", "pl"
      t.string :field, null: false             # the translated attribute
      t.text :value                            # the per-locale content
      t.timestamps
    end
    add_index :open_loam_translations, %i[translatable_type translatable_id locale field],
              unique: true, name: "index_loam_translations_unique"
  end
end
