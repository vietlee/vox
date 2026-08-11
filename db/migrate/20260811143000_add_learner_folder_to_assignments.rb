class AddLearnerFolderToAssignments < ActiveRecord::Migration[7.2]
  def change
    # Track which class an assignment was made through, so the learner app can
    # show "content assigned from this class". Nullable: individually-assigned
    # content (not via a class) has no folder.
    %i[quiz_assignments flashcard_assignments learning_path_assignments].each do |table|
      add_reference table, :learner_folder, null: true, foreign_key: true
    end
  end
end
