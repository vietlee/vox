class Learner < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable,
         :rememberable, :trackable

  has_many :learner_payments,            dependent: :destroy
  has_many :learner_suggestions,         dependent: :destroy
  has_many :learner_daily_stats,         dependent: :destroy
  has_many :learner_study_plans,         dependent: :destroy
  has_many :learner_speaking_sessions,   dependent: :destroy
  has_many :learner_badges,              dependent: :destroy
  has_many :learner_daily_challenges,    dependent: :destroy
  has_many :learner_push_subscriptions,  dependent: :destroy
  has_many :learner_notifications,       dependent: :destroy
  has_many :learner_saved_links,         dependent: :destroy
  has_many :flashcard_reviews,           dependent: :destroy, foreign_key: :learner_id
  has_many :quiz_assignments,           dependent: :destroy
  has_many :flashcard_assignments,      dependent: :destroy
  has_many :learning_path_assignments,  dependent: :destroy, foreign_key: :learner_id
  has_many :quiz_sets,      through: :quiz_assignments
  has_many :flashcard_decks, through: :flashcard_assignments
  has_many :learning_paths,  through: :learning_path_assignments

  # Referral: who invited me, and everyone I invited.
  belongs_to :referrer, class_name: "Learner", foreign_key: :referred_by_id, optional: true
  has_many   :referrals, class_name: "Learner", foreign_key: :referred_by_id, dependent: :nullify

  before_create :ensure_referral_code

  validates :name,  presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }

  MONTHLY_FREE_CREDITS = 50
  REFERRAL_REWARD      = 50   # credits granted to BOTH inviter and new user

  # A short unique code used in invite links / QR codes.
  def ensure_referral_code
    return if referral_code.present?
    loop do
      self.referral_code = SecureRandom.alphanumeric(7).upcase
      break unless Learner.exists?(referral_code: referral_code)
    end
  end

  def deduct_credits!(amount)
    raise "Không đủ credit" if credits < amount
    decrement!(:credits, amount)
  end

  # Called when a learner purchases credits
  def add_credits!(amount)
    increment!(:credits, amount)
    increment!(:max_credits, amount)
  end

  # Called by MonthlyFreeResetJob on the 1st of each month
  def reset_monthly_credits!
    update_columns(credits: MONTHLY_FREE_CREDITS, max_credits: MONTHLY_FREE_CREDITS)
  end

  def invite!(assigned_by:)
    self.invite_token = SecureRandom.urlsafe_base64(24)
    self.invite_sent_at = Time.current
    self.password = SecureRandom.hex(16)
    save!
    LearnerMailer.invite(self, assigned_by).deliver_later
  end

  def self.find_or_invite!(email:, name:, assigned_by:)
    learner = find_or_initialize_by(email: email.downcase.strip)
    if learner.new_record?
      learner.name = name.presence || email.split("@").first.capitalize
      learner.invite!(assigned_by: assigned_by)
    end
    learner
  end

end
