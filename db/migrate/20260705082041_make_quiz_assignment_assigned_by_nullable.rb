class MakeQuizAssignmentAssignedByNullable < ActiveRecord::Migration[7.2]
  def change
    change_column_null :quiz_assignments, :assigned_by_id, true
  end
end
