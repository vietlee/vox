class FlashcardDeck < ApplicationRecord
  belongs_to :workspace
  belongs_to :created_by, class_name: "User"
  has_many :flashcards, -> { order(:position) }, dependent: :destroy

  def due_count_for(user)
    flashcards.joins(:flashcard_reviews)
              .where(flashcard_reviews: { user: user })
              .where("flashcard_reviews.next_review_at <= ?", Time.current)
              .count
  end
end
