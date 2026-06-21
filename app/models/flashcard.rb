class Flashcard < ApplicationRecord
  belongs_to :flashcard_deck
  has_many :flashcard_reviews, dependent: :destroy

  def review_for(user)
    flashcard_reviews.find_by(user: user)
  end

  # SM-2 spaced repetition
  def self.next_interval(rating, ease, interval)
    case rating
    when 0 then [1, ease, 1]                           # again
    when 1 then [ease - 0.15, ease - 0.15, 1]          # hard
    when 2 then [ease, ease, (interval * ease).ceil]   # good
    when 3 then [ease + 0.1, ease + 0.1, (interval * ease * 1.3).ceil] # easy
    end
  end
end
