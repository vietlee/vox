class QuizSet < ApplicationRecord
  belongs_to :workspace
  belongs_to :user

  has_many :quiz_questions, -> { order(:position) }, dependent: :destroy
  has_many :quiz_attempts,  dependent: :destroy

  enum :status,      { draft: 0, published: 1 }
  enum :source_type, { manual: 0, ai_generated: 1 }
  enum :result_mode, { result_immediate: 0, result_later: 1 }

  validates :title, presence: true
  validates :share_token, presence: true, uniqueness: true

  before_validation :generate_share_token, on: :create

  def question_count = quiz_questions.count
  def attempt_count  = quiz_attempts.where.not(submitted_at: nil).count

  def avg_score
    attempts = quiz_attempts.where.not(submitted_at: nil)
    return nil if attempts.empty?
    (attempts.sum(:score).to_f / attempts.count).round(1)
  end

  private

  def generate_share_token
    self.share_token ||= SecureRandom.urlsafe_base64(10)
  end
end
