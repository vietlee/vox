class AddTotalScoreAndPassingScoreTypeToQuizSets < ActiveRecord::Migration[7.2]
  def change
    add_column :quiz_sets, :total_score, :integer
    add_column :quiz_sets, :passing_score_type, :string, default: 'percent', null: false
  end
end
