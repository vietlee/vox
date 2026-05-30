class FeedbackReply < ApplicationRecord
  belongs_to :feedback
  has_many_attached :images

  validates :content, presence: true, length: { maximum: 500 }
end
