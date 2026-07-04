class Learner < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable,
         :rememberable, :trackable, :confirmable

  has_many :quiz_assignments,           dependent: :destroy
  has_many :flashcard_assignments,      dependent: :destroy
  has_many :learning_path_assignments,  dependent: :destroy, foreign_key: :learner_id
  has_many :quiz_sets,      through: :quiz_assignments
  has_many :flashcard_decks, through: :flashcard_assignments
  has_many :learning_paths,  through: :learning_path_assignments

  validates :name,  presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }

  before_create :skip_confirmation_for_invite

  def deduct_credits!(amount)
    raise "Không đủ credit" if credits < amount
    decrement!(:credits, amount)
  end

  def invite!(assigned_by:)
    self.invite_token = SecureRandom.urlsafe_base64(24)
    self.invite_sent_at = Time.current
    self.password = SecureRandom.hex(16)
    self.skip_confirmation!
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

  private

  def skip_confirmation_for_invite
    skip_confirmation! if invite_token.present?
  end
end
