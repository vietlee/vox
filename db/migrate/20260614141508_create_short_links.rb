class CreateShortLinks < ActiveRecord::Migration[7.2]
  def change
    create_table :short_links do |t|
      t.string :code, null: false
      t.string :target_url, null: false
      t.references :workspace, null: true, foreign_key: true
      t.integer :clicks_count, default: 0, null: false

      t.timestamps
    end
    add_index :short_links, :code, unique: true
    add_index :short_links, :target_url
  end
end
