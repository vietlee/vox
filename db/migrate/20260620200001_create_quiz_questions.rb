class CreateQuizQuestions < ActiveRecord::Migration[7.2]
  def change
    create_table :quiz_questions do |t|
      t.references :quiz_set, null: false, foreign_key: true
      t.text    :question_text, null: false
      t.integer :question_type, null: false, default: 0  # multiple_choice / true_false / short_answer
      t.text    :explanation
      t.integer :position, null: false, default: 0
      t.integer :points, null: false, default: 1
      t.timestamps
    end
    add_index :quiz_questions, [:quiz_set_id, :position]
  end
end
