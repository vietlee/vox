class FlashcardReview < ApplicationRecord
  belongs_to :flashcard
  belongs_to :user

  enum :rating, { again: 0, hard: 1, good: 2, easy: 3 }
end
