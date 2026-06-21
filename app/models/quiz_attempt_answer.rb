class QuizAttemptAnswer < ApplicationRecord
  belongs_to :quiz_attempt
  belongs_to :quiz_question
  belongs_to :quiz_option, optional: true
end
