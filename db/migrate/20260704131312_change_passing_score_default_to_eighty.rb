class ChangePassingScoreDefaultToEighty < ActiveRecord::Migration[7.2]
  def change
    change_column_default :quiz_sets, :passing_score, from: 50, to: 80
  end
end
