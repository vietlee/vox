class FeedbackReply < ApplicationRecord
  belongs_to :feedback

  validates :content, presence: true, length: { maximum: 500 }
end
