class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable,
         :rememberable, :trackable, :confirmable, :lockable,
         :timeoutable, :two_factor_authenticatable, :omniauthable,
         timeout_in: 60.days,
         otp_secret_encryption_key: ENV.fetch("OTP_ENCRYPTION_KEY", "a" * 32),
         omniauth_providers: [:google_oauth2, :entra_id]

  belongs_to :workspace, optional: true
  has_many :owned_workspaces, class_name: "Workspace", foreign_key: :owner_id, dependent: :nullify

  # The one subscription that holds this user's shared credit budget.
  # All workspaces they own draw from this single pool.
  def primary_subscription
    primary_ws = owned_workspaces.order(:id).first
    primary_ws&.active_subscription
  end
  has_many :workspace_memberships, dependent: :destroy
  has_many :workspaces, through: :workspace_memberships
  has_many :surveys, dependent: :nullify
  has_many :votes, dependent: :nullify
  has_many :feedback_boards, dependent: :nullify
  has_many :ai_jobs, dependent: :nullify
  has_many :audit_logs, dependent: :nullify
  has_many :notifications, dependent: :destroy

  enum :role,   { super_admin: 0, admin: 1, supporter: 2, participant: 3 }
  enum :status, { active: 0, inactive: 1 }

  validates :name,  presence: true, length: { maximum: 100 }
  validates :email, presence: true
  validates :role,  presence: true
  validates :uid,   uniqueness: { scope: :provider }, allow_nil: true

  # Skip password validation for OAuth users
  def password_required?
    super && provider.blank?
  end

  scope :workspace_members, -> { where.not(role: :super_admin) }

  # ── OmniAuth ──────────────────────────────────────────────────────────────
  def self.from_omniauth(auth)
    # Find by provider+uid first (returning user)
    user = find_by(provider: auth.provider, uid: auth.uid)
    # Fall back to email match (existing account, linking provider)
    user ||= find_by(email: auth.info.email)

    if user
      # Link provider if not already linked
      user.update_columns(provider: auth.provider, uid: auth.uid) if user.uid.blank?
      # Auto-confirm: Google/Microsoft already verified the email
      user.update_column(:confirmed_at, Time.current) if user.confirmed_at.nil?
      return user
    end

    # New user — caller decides role/workspace
    new(
      provider:     auth.provider,
      uid:          auth.uid,
      email:        auth.info.email,
      name:         auth.info.name.presence || auth.info.email.split("@").first,
      password:     Devise.friendly_token[0, 20],
      confirmed_at: Time.current
    )
  end

  def super_admin?
    role == "super_admin"
  end

  def workspace_admin?
    role == "admin"
  end

  def supporter?
    role == "supporter"
  end

  def participant?
    role == "participant"
  end

  # Can access the admin dashboard
  def workspace_member?
    admin? || supporter? || super_admin?
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
