class AddResultModeToQuizSets < ActiveRecord::Migration[7.2]
  def change
    add_column :quiz_sets, :result_mode, :integer, default: 0, null: false
  end
end
