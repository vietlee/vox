class AddAiGeneratingFlags < ActiveRecord::Migration[7.2]
  def change
    add_column :flashcard_decks, :ai_generating, :boolean, default: false
    add_column :learning_paths,  :ai_generating, :boolean, default: false
    add_column :quiz_sets,       :ai_generating, :boolean, default: false
  end
end
