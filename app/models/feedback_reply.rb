class FeedbackReply < ApplicationRecord
  belongs_to :feedback
  has_one_attached :image

  validates :content, presence: true, length: { maximum: 500 }
end
