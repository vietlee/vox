class AddFlashcardDeckToLearningPathItems < ActiveRecord::Migration[7.2]
  def change
    add_column :learning_path_items, :flashcard_deck_id, :bigint
  end
end
