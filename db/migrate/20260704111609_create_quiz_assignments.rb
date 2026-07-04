class CreateQuizAssignments < ActiveRecord::Migration[7.2]
  def change
    create_table :quiz_assignments do |t|
      t.references :quiz_set,     null: false, foreign_key: true
      t.references :learner,      null: false, foreign_key: true
      t.bigint     :assigned_by_id, null: false
      t.string     :token,        null: false
      t.integer    :status,       default: 0, null: false
      t.datetime   :due_at
      t.text       :message
      t.datetime   :completed_at
      t.timestamps
    end

    add_index :quiz_assignments, :token, unique: true
    add_index :quiz_assignments, [:quiz_set_id, :learner_id], unique: true
  end
end
