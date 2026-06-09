class AddEditTokenToResponses < ActiveRecord::Migration[7.2]
  def change
    add_column :responses, :edit_token, :string
    add_index :responses, :edit_token, unique: true
  end
end
