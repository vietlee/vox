class LearningPathItem < ApplicationRecord
  belongs_to :learning_path
  belongs_to :quiz_set, optional: true
  belongs_to :flashcard_deck, optional: true
  has_many :learning_item_progresses, dependent: :destroy

  enum :item_type, { lesson: 0, quiz: 1, flashcard: 2 }
end
