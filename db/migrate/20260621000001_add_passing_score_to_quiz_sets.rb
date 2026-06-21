class AddPassingScoreToQuizSets < ActiveRecord::Migration[7.2]
  def change
    add_column :quiz_sets, :passing_score, :integer, default: 50, null: false
  end
end
