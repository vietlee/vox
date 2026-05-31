class Feedback < ApplicationRecord
  belongs_to :feedback_board
  belongs_to :workspace
  has_many   :feedback_upvotes, dependent: :destroy
  has_many   :feedback_replies, dependent: :destroy
  has_many_attached :images
  has_one_attached  :admin_reply_image

  enum :status,            { pending: 0, approved: 1, hidden: 2, rejected: 3 }
  enum :admin_status,      { new_feedback: 0, under_review: 1, implemented: 2, declined: 3 }
  enum :moderation_status, { moderation_pending: 0, safe: 1, flagged: 2, auto_rejected: 3 }

  validates :content, presence: true, length: { maximum: 1000 }
  validate :require_name_for_public_identity

  scope :visible,      -> { where(status: :approved).where.not(moderation_status: :flagged) }
  scope :pinned_first, -> { order(pinned: :desc, created_at: :desc) }

  after_create :enqueue_ai_moderation

  def approve!
    update!(status: :approved)
  end

  def upvoted_by?(token)
    feedback_upvotes.exists?(voter_token: token)
  end

  private

  def require_name_for_public_identity
    if feedback_board&.public_identity?
      errors.add(:author_name, :blank) if author_name.blank?
    elsif feedback_board&.user_choice? && !anonymous? && author_name.blank?
      errors.add(:base, :must_choose_anonymous_or_name)
    end
  end

  def enqueue_ai_moderation
    return unless feedback_board.auto_moderation?
    AiModerationJob.perform_later(id)
  end
end
