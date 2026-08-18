class AddPasswordsToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :password_digest, :string

    # Demo rows predate passwords and may have no email at all. Give them a
    # placeholder so the NOT NULL + unique index can go on; db:seed then sets
    # the real address and password for the named users.
    execute "UPDATE users SET email = 'user' || id || '@example.test' WHERE email IS NULL OR email = ''"

    change_column_null :users, :email, false
    add_index :users, :email, unique: true
  end

  def down
    remove_index :users, :email
    change_column_null :users, :email, true
    remove_column :users, :password_digest
  end
end
