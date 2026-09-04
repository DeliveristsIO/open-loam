class CreateLoamTranslations < ActiveRecord::Migration[8.1]
  def change
    create_table :loam_translations do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }
      t.string :translatable_type, null: false
      t.bigint :translatable_id, null: false
      t.string :locale, null: false            # "en", "de", "pl"
      t.string :field, null: false             # the translated attribute
      t.text :value                            # the per-locale content
      t.timestamps
    end
    add_index :loam_translations, %i[translatable_type translatable_id locale field],
              unique: true, name: "index_loam_translations_unique"
  end
end
