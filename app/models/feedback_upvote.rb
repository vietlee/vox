class FeedbackUpvote < ApplicationRecord
  belongs_to :feedback

  validates :voter_token, presence: true
  validates :voter_token, uniqueness: { scope: :feedback_id }

  after_create  { feedback.increment!(:upvotes_count) }
  after_destroy { feedback.decrement!(:upvotes_count) }
end
