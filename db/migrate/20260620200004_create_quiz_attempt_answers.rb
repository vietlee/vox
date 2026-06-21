class CreateQuizAttemptAnswers < ActiveRecord::Migration[7.2]
  def change
    create_table :quiz_attempt_answers do |t|
      t.references :quiz_attempt,  null: false, foreign_key: true
      t.references :quiz_question, null: false, foreign_key: true
      t.references :quiz_option,   null: true,  foreign_key: true
      t.text    :text_answer
      t.boolean :is_correct, null: false, default: false
      t.timestamps
    end
  end
end
