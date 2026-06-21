class AddMultipleSelectToQuizQuestions < ActiveRecord::Migration[7.2]
  def change
    # multiple_select: 3 — add allow_multiple column to quiz_questions
    add_column :quiz_questions, :allow_multiple, :boolean, null: false, default: false
  end
end
