class FlashcardReview < ApplicationRecord
  belongs_to :flashcard
  belongs_to :user, optional: true
  belongs_to :learner, optional: true

  enum :rating, { again: 0, hard: 1, good: 2, easy: 3 }

  def self.for_learner_card(learner_id, flashcard_id)
    find_or_initialize_by(learner_id: learner_id, flashcard_id: flashcard_id)
  end
end
