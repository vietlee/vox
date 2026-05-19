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

  private

  def generate_slug
    self.slug ||= self.class.slugify(name) if name.present?
  end
end
