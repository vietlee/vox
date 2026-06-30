class AddAiFeedbackToLearningPathAssignments < ActiveRecord::Migration[7.2]
  def change
    add_column :learning_path_assignments, :ai_feedback, :text
    add_column :learning_path_assignments, :ai_feedback_at, :datetime
  end
end
