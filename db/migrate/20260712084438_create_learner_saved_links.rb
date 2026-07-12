class CreateLearnerSavedLinks < ActiveRecord::Migration[7.2]
  def change
    create_table :learner_saved_links do |t|
      t.references :learner, null: false, foreign_key: true
      t.text :url, null: false
      t.string :title
      t.text :description
      t.string :thumbnail
      t.string :favicon
      t.string :category, null: false, default: 'learning'
      t.string :link_type, null: false, default: 'generic'
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :learner_saved_links, [:learner_id, :position]
  end
end
