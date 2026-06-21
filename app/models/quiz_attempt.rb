class QuizAttempt < ApplicationRecord
  belongs_to :quiz_set
  has_many :quiz_attempt_answers, dependent: :destroy

  validates :participant_name,  presence: true
  validates :participant_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  before_create :generate_result_token

  def submitted? = submitted_at.present?
  def score_pct  = total_points > 0 ? (earned_points * 100.0 / total_points).round : 0
  def passed?    = score_pct >= (quiz_set.passing_score || 50)

  private

  def generate_result_token
    loop do
      self.result_token = SecureRandom.urlsafe_base64(16)
      break unless self.class.exists?(result_token: result_token)
    end
  end
end
