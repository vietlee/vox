class AddAiAnalysisToLearners < ActiveRecord::Migration[7.2]
  def change
    add_column :learners, :ai_analysis_html, :text
    add_column :learners, :ai_analyzed_at, :datetime
  end
end
