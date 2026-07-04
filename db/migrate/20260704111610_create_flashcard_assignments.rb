class CreateFlashcardAssignments < ActiveRecord::Migration[7.2]
  def change
    create_table :flashcard_assignments do |t|
      t.references :flashcard_deck, null: false, foreign_key: true
      t.references :learner,        null: false, foreign_key: true
      t.bigint     :assigned_by_id, null: false
      t.string     :token,          null: false
      t.integer    :status,         default: 0, null: false
      t.datetime   :due_at
      t.datetime   :completed_at
      t.timestamps
    end

    add_index :flashcard_assignments, :token, unique: true
    add_index :flashcard_assignments, [:flashcard_deck_id, :learner_id], unique: true
  end
end
