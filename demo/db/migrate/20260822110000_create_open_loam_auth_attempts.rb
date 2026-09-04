class CreateLoamAuthAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :loam_auth_attempts do |t|
      t.string :identifier, null: false   # the submitted login (normalized), NOT tenant-scoped
      t.string :kind, null: false         # password / totp / recovery / sudo
      t.string :ip                        # nullable; for an optional per-ip throttle
      t.timestamps
    end
    add_index :loam_auth_attempts, %i[identifier created_at]
  end
end
