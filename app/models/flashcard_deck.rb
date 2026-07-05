class FlashcardDeck < ApplicationRecord
  belongs_to :workspace,   optional: true
  belongs_to :created_by,  class_name: "User", optional: true
  belongs_to :learner,     optional: true
  has_many :flashcards,            -> { order(:position) }, dependent: :destroy
  has_many :flashcard_assignments, dependent: :destroy

  validates :title, presence: true, length: { maximum: 150 }

  def due_count_for(user)
    flashcards.joins(:flashcard_reviews)
              .where(flashcard_reviews: { user: user })
              .where("flashcard_reviews.next_review_at <= ?", Time.current)
              .count
  end
end
