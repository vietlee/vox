class AddAiEvaluationToQuizAttempts < ActiveRecord::Migration[7.2]
  def change
    add_column :quiz_attempts, :ai_evaluation, :text
    add_column :quiz_attempts, :ai_evaluated_at, :datetime
  end
end
