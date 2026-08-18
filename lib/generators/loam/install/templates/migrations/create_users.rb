class CreateUsers < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email
      t.timestamps
    end
  end
end
