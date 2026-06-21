class AddAiEvaluationToQuizSets < ActiveRecord::Migration[7.2]
  def change
    add_column :quiz_sets, :ai_class_evaluation, :text
    add_column :quiz_sets, :ai_class_evaluated_at, :datetime
  end
end
