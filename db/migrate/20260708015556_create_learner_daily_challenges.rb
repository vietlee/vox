class CreateLearnerDailyChallenges < ActiveRecord::Migration[7.2]
  def change
    create_table :learner_daily_challenges do |t|
      t.references :learner, null: false, foreign_key: true
      t.date :challenge_date, null: false
      t.jsonb :questions, default: []
      t.jsonb :submitted_answers, default: {}
      t.integer :score, default: 0
      t.integer :total, default: 5
      t.boolean :completed, default: false
      t.datetime :completed_at
      t.timestamps
    end
    add_index :learner_daily_challenges, [:learner_id, :challenge_date], unique: true
  end
end
