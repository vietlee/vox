class CreateLearnerBadges < ActiveRecord::Migration[7.2]
  def change
    create_table :learner_badges do |t|
      t.references :learner, null: false, foreign_key: true
      t.string :key, null: false
      t.datetime :earned_at, null: false
      t.timestamps
    end
    add_index :learner_badges, [:learner_id, :key], unique: true
  end
end
