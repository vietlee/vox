class AddImageGeneratingToFlashcardDecks < ActiveRecord::Migration[7.2]
  def change
    add_column :flashcard_decks, :image_generating, :boolean, default: false
  end
end
