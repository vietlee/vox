class QuizAssignment < ApplicationRecord
  belongs_to :quiz_set
  belongs_to :learner
  belongs_to :assigned_by, class_name: "User", optional: true

  enum :status, { pending: 0, in_progress: 1, completed: 2 }

  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create

  def overdue?
    due_at.present? && due_at < Time.current && !completed?
  end

  def answered_count
    return quiz_set.quiz_questions.count if completed?
    attempt = quiz_set.quiz_attempts.find_by(participant_email: learner.email)
    return 0 unless attempt
    attempt.quiz_attempt_answers.where.not(quiz_option_id: nil).count
  end

  def progress_pct
    total = quiz_set.quiz_questions.count
    return 100 if completed? || total == 0
    (answered_count * 100.0 / total).round
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(20)
  end
end
