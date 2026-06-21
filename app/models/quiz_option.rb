class QuizOption < ApplicationRecord
  belongs_to :quiz_question
  has_many :quiz_attempt_answers, dependent: :nullify

  validates :option_text, presence: true
end
