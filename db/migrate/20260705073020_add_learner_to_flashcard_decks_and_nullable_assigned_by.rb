class AddLearnerToFlashcardDecksAndNullableAssignedBy < ActiveRecord::Migration[7.2]
  def change
    change_column_null :flashcard_decks, :workspace_id,  true
    change_column_null :flashcard_decks, :created_by_id, true
    add_column         :flashcard_decks, :learner_id,     :bigint, null: true
    add_index          :flashcard_decks, :learner_id

    change_column_null :flashcard_assignments, :assigned_by_id, true
  end
end
