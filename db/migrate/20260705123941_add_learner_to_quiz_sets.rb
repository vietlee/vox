class AddLearnerToQuizSets < ActiveRecord::Migration[7.2]
  def change
    change_column_null :quiz_sets, :workspace_id, true
    change_column_null :quiz_sets, :user_id,      true
    add_column :quiz_sets, :learner_id, :bigint
    add_index  :quiz_sets, :learner_id
  end
end
