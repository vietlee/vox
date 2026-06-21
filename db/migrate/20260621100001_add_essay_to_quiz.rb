class AddEssayToQuiz < ActiveRecord::Migration[7.2]
  def change
    # question_type đã có (0=multiple_choice), 1=essay sẽ dùng qua enum
    # Thêm rubric chấm điểm cho câu tự luận
    add_column :quiz_questions,       :essay_rubric,   :text     unless column_exists?(:quiz_questions, :essay_rubric)

    # Bài viết tự luận + kết quả AI chấm
    add_column :quiz_attempt_answers, :essay_text,     :text     unless column_exists?(:quiz_attempt_answers, :essay_text)
    add_column :quiz_attempt_answers, :ai_grade,       :integer  unless column_exists?(:quiz_attempt_answers, :ai_grade)
    add_column :quiz_attempt_answers, :ai_feedback,    :text     unless column_exists?(:quiz_attempt_answers, :ai_feedback)
    add_column :quiz_attempt_answers, :ai_graded_at,   :datetime unless column_exists?(:quiz_attempt_answers, :ai_graded_at)
  end
end
