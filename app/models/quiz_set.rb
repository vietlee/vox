class QuizSet < ApplicationRecord
  belongs_to :workspace, optional: true
  belongs_to :user,      optional: true
  belongs_to :learner,   optional: true

  has_many :quiz_questions,   -> { order(:position) }, dependent: :destroy
  has_many :quiz_attempts,    dependent: :destroy
  has_many :quiz_assignments, dependent: :destroy
  has_one  :qr_code, as: :resource, dependent: :destroy

  enum :status,      { draft: 0, published: 1 }
  enum :source_type, { manual: 0, ai_generated: 1 }
  enum :result_mode, { result_immediate: 0, result_later: 1 }

  validates :title, presence: true
  validates :share_token, presence: true, uniqueness: true

  before_validation :generate_share_token, on: :create

  def question_count = quiz_questions.count
  def attempt_count  = quiz_attempts.where.not(submitted_at: nil).count
  def has_essay?     = quiz_questions.where(question_type: :essay).exists?

  def computed_total_score
    total_score.presence || quiz_questions.sum(:points)
  end

  def passing_score_points
    return passing_score if passing_score_type == 'points'
    (computed_total_score * passing_score / 100.0).ceil
  end

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
