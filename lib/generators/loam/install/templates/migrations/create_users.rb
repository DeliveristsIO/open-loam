class CreateUsers < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :password_digest, null: false
      t.timestamps
    end
    # Email is the login, so uniqueness is enforced by the database, not only
    # by the model.
    add_index :users, :email, unique: true
  end
end
