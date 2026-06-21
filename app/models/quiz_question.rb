class QuizQuestion < ApplicationRecord
  belongs_to :quiz_set
  has_many :quiz_options,         -> { order(:position) }, dependent: :destroy
  has_many :quiz_attempt_answers, dependent: :destroy

  enum :question_type, { multiple_choice: 0, true_false: 1, short_answer: 2, essay: 3 }

  validates :question_text, presence: true

  def has_options? = multiple_choice? || true_false?
  def correct_options = quiz_options.where(is_correct: true)
  def needs_ai_grading? = essay?
end
