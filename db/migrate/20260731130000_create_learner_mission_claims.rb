class CreateLearnerMissionClaims < ActiveRecord::Migration[7.2]
  def change
    create_table :learner_mission_claims do |t|
      t.bigint  :learner_id,  null: false
      t.string  :mission_key, null: false
      t.string  :period,      null: false   # "YYYY-MM-DD" for daily, "once" for milestones
      t.integer :reward,      null: false, default: 0
      t.datetime :claimed_at, null: false
      t.timestamps
    end
    add_index :learner_mission_claims, [:learner_id, :mission_key, :period], unique: true,
              name: "idx_mission_claims_unique"
    add_index :learner_mission_claims, :learner_id
  end
end
