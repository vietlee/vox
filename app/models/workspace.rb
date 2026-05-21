class Workspace < ApplicationRecord
  include Sluggable
  has_many :users, dependent: :destroy
  has_many :workspace_memberships, dependent: :destroy
  has_many :members, through: :workspace_memberships, source: :user
  has_many :subscriptions, dependent: :destroy
  has_many :surveys, dependent: :destroy
  has_many :votes, dependent: :destroy
  has_many :feedback_boards, dependent: :destroy
  has_many :ai_jobs, dependent: :destroy
  has_many :payments, dependent: :destroy
  has_many :audit_logs, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :qr_codes, dependent: :destroy
  has_one  :current_subscription, -> { where(status: :active).order(created_at: :desc) }, class_name: "Subscription"

  enum :status, { active: 0, inactive: 1, suspended: 2 }

  validates :name, presence: true, length: { maximum: 100 }
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }
  validates :brand_color, format: { with: /\A#[0-9A-Fa-f]{6}\z/ }, allow_blank: true

  before_validation :generate_slug, on: :create

  def admin_users
    users.where(role: :admin)
  end

  def supporters
    users.where(role: :supporter)
  end

  def active_subscription
    subscriptions.active
                 .where("ends_at IS NULL OR ends_at > ?", Time.current)
                 .order(created_at: :desc).first
  end

  def plan
    active_subscription&.plan || "free"
  end

  def ai_credits_remaining
    active_subscription&.credit_balance || 0
  end

  # Hard-delete workspace and ALL related data in FK-safe order
  def purge!
    ActiveRecord::Base.transaction do
      wid = id

      survey_ids  = Survey.where(workspace_id: wid).pluck(:id)
      vote_ids    = Vote.where(workspace_id: wid).pluck(:id)
      fb_ids      = FeedbackBoard.where(workspace_id: wid).pluck(:id)
      fb_item_ids = Feedback.where(feedback_board_id: fb_ids).pluck(:id)
      q_ids       = Question.where(survey_id: survey_ids).pluck(:id)
      aj_ids      = AiJob.where(workspace_id: wid).pluck(:id)

      # 1. AiAnalysisResult
      AiAnalysisResult.where(workspace_id: wid).delete_all
      AiAnalysisResult.where(ai_job_id: aj_ids).delete_all if aj_ids.any?

      # 2. Survey children
      Answer.where(question_id: q_ids).delete_all if q_ids.any?
      QuestionOption.where(question_id: q_ids).delete_all if q_ids.any?
      Question.where(survey_id: survey_ids).delete_all if survey_ids.any?
      Response.where(workspace_id: wid).delete_all
      Survey.where(workspace_id: wid).delete_all

      # 3. Vote children
      VoteResponse.where(workspace_id: wid).delete_all
      VoteOption.where(vote_id: vote_ids).delete_all if vote_ids.any?
      Vote.where(workspace_id: wid).delete_all

      # 4. Feedback children
      FeedbackUpvote.where(feedback_id: fb_item_ids).delete_all if fb_item_ids.any?
      FeedbackReply.where(feedback_id: fb_item_ids).delete_all if fb_item_ids.any?
      Feedback.where(feedback_board_id: fb_ids).delete_all if fb_ids.any?
      FeedbackBoard.where(workspace_id: wid).delete_all

      # 5. Workspace meta
      QrCode.where(workspace_id: wid).delete_all
      Payment.where(workspace_id: wid).delete_all
      Subscription.where(workspace_id: wid).delete_all
      AiJob.where(workspace_id: wid).delete_all
      AuditLog.where(workspace_id: wid).delete_all
      Notification.where(workspace_id: wid).delete_all
      WorkspaceMembership.where(workspace_id: wid).delete_all

      # 6. Users belonging to this workspace (admin/supporter) — not super_admin
      User.where(workspace_id: wid).where.not(role: :super_admin).delete_all

      # 7. Workspace itself
      delete
    end
  end

  private

  def generate_slug
    self.slug ||= self.class.slugify(name) if name.present?
  end
end
