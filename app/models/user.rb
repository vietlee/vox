class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable,
         :rememberable, :trackable, :confirmable, :lockable,
         :timeoutable, :two_factor_authenticatable,
         timeout_in: 60.days,
         otp_secret_encryption_key: ENV.fetch("OTP_ENCRYPTION_KEY", "a" * 32)

  belongs_to :workspace, optional: true
  has_many :workspace_memberships, dependent: :destroy
  has_many :workspaces, through: :workspace_memberships
  has_many :surveys, dependent: :nullify
  has_many :votes, dependent: :nullify
  has_many :feedback_boards, dependent: :nullify
  has_many :ai_jobs, dependent: :nullify
  has_many :audit_logs, dependent: :nullify
  has_many :notifications, dependent: :destroy

  enum :role,   { super_admin: 0, admin: 1, supporter: 2 }
  enum :status, { active: 0, inactive: 1 }

  validates :name, presence: true, length: { maximum: 100 }
  validates :email, presence: true
  validates :role,  presence: true

  scope :workspace_members, -> { where.not(role: :super_admin) }

  def super_admin?
    role == "super_admin"
  end

  def workspace_admin?
    role == "admin"
  end

  def supporter?
    role == "supporter"
  end

  def can_access_ai?
    workspace&.active_subscription&.has_feature?(:ai_analysis)
  end

  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_later
  end

  def display_name
    name.presence || email.split("@").first
  end

  def initials
    name.split.map(&:first).join.upcase.first(2)
  end
end
