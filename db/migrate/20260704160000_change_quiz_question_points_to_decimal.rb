class ChangeQuizQuestionPointsToDecimal < ActiveRecord::Migration[7.2]
  def up
    change_column :quiz_questions, :points, :decimal, precision: 5, scale: 1, default: 1.0, null: false
  end

  def down
    change_column :quiz_questions, :points, :integer, default: 1, null: false
  end
end
