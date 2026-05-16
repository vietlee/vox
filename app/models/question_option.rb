class QuestionOption < ApplicationRecord
  belongs_to :question
  has_many   :answers, through: :question

  validates :label, presence: true
  validates :position, numericality: { greater_than_or_equal_to: 0 }

  default_scope { order(:position) }
end
