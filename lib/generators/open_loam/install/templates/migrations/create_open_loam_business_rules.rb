class CreateOpenLoamBusinessRules < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_business_rules<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.string :name, null: false
      t.string :entity_type              # the entity this rule watches (nil = event-only)
      t.string :trigger, null: false     # an event pattern (OpenLoam::Events.pattern_matches?)
      t.json :condition, null: false, default: {}   # a safe condition tree (data, never code)
      t.json :actions, null: false, default: []     # an ordered list of typed action descriptors
      t.boolean :active, null: false, default: true
      t.integer :priority, null: false, default: 0
      t.timestamps
    end
    add_index :open_loam_business_rules, %i[tenant_id active]

    create_table :open_loam_business_rule_runs<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.references :business_rule, null: false, foreign_key: { to_table: :open_loam_business_rules }<%= open_loam_type_option %>
      t.string :subject_type
      t.<%= open_loam_key_column_type %> :subject_id<%= open_loam_key_limit_option %>
      t.string :event_name
      t.boolean :matched, null: false, default: false
      t.json :actions_taken, null: false, default: []
      t.text :error
      t.timestamps
    end
    add_index :open_loam_business_rule_runs, %i[tenant_id business_rule_id created_at]
  end
end
