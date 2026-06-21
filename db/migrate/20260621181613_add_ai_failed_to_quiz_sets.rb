class AddAiFailedToQuizSets < ActiveRecord::Migration[7.2]
  def change
    add_column :quiz_sets, :ai_failed, :boolean, default: false, null: false
  end
end
