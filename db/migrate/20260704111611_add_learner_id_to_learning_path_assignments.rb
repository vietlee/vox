class AddLearnerIdToLearningPathAssignments < ActiveRecord::Migration[7.2]
  def change
    add_column :learning_path_assignments, :learner_id, :bigint
    add_column :learning_path_assignments, :token,      :string
    add_column :learning_path_assignments, :completed_at, :datetime
    add_index  :learning_path_assignments, :token, unique: true
    add_index  :learning_path_assignments, :learner_id
    # Make assignee_id optional (learner assignments don't have a User assignee)
    change_column_null :learning_path_assignments, :assignee_id, true
  end
end
