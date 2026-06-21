class CreateQuizSets < ActiveRecord::Migration[7.2]
  def change
    create_table :quiz_sets do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string  :title,       null: false
      t.text    :description
      t.integer :status,      null: false, default: 0  # draft / published
      t.integer :source_type, null: false, default: 0  # manual / ai_generated
      t.string  :share_token, null: false
      t.boolean :allow_retake,   null: false, default: true
      t.boolean :show_answers,   null: false, default: true
      t.integer :time_limit_minutes
      t.timestamps
    end
    add_index :quiz_sets, :share_token, unique: true
    add_index :quiz_sets, [:workspace_id, :status]
  end
end
