class CreateOpenLoamAuthAttempts < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_auth_attempts<%= open_loam_id_option %> do |t|
      t.string :identifier, null: false   # the submitted login (normalized), NOT tenant-scoped
      t.string :kind, null: false         # password / totp / recovery / sudo
      t.string :ip                        # nullable; for an optional per-ip throttle
      t.timestamps
    end
    add_index :open_loam_auth_attempts, %i[identifier created_at]
  end
end
