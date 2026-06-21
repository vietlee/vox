class AddImageDataToFlashcards < ActiveRecord::Migration[7.2]
  def change
    add_column :flashcards, :image_data, :text
  end
end
