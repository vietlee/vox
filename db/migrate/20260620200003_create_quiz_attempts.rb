class CreateQuizAttempts < ActiveRecord::Migration[7.2]
  def change
    create_table :quiz_attempts do |t|
      t.references :quiz_set, null: false, foreign_key: true
      t.string  :participant_name,  null: false
      t.string  :participant_email, null: false
      t.integer :score,            null: false, default: 0
      t.integer :total_questions,  null: false, default: 0
      t.integer :total_points,     null: false, default: 0
      t.integer :earned_points,    null: false, default: 0
      t.datetime :submitted_at
      t.integer  :time_spent_seconds
      t.timestamps
    end
    add_index :quiz_attempts, [:quiz_set_id, :participant_email]
  end
end
