class AddProgressToAssignments < ActiveRecord::Migration[7.2]
  def change
    add_column :flashcard_assignments, :cards_reviewed, :integer, default: 0, null: false
  end
end
