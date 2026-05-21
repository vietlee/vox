class Response < ApplicationRecord
  belongs_to :survey
  belongs_to :workspace
  has_many   :answers, dependent: :destroy

  enum :status, { in_progress: 0, completed: 1 }

  validates :survey, :workspace, presence: true
  validate :prevent_duplicate_response, on: :create

  scope :completed, -> { where(status: :completed) }
  scope :quality,   -> { where(excluded: false) }

  after_create :increment_survey_counter

  def complete!
    update!(
      status: :completed,
      completed_at: Time.current,
      completion_time_seconds: (Time.current - created_at).to_i
    )
    survey.increment!(:response_count)
  end

  private

  def increment_survey_counter
    # response_count will be incremented on complete!
  end

  def prevent_duplicate_response
    return if survey.nil?
    return unless survey.max_per_user.to_i > 0

    completed = survey.responses.completed
    # Check by user_id first (covers all devices/browsers for logged-in users)
    if user_id.present? && completed.exists?(user_id: user_id)
      errors.add(:base, :already_responded) and return
    end
    if respondent_token.present? && completed.exists?(respondent_token: respondent_token)
      errors.add(:base, :already_responded) and return
    end
    if respondent_email.present? && completed.exists?(respondent_email: respondent_email)
      errors.add(:base, :already_responded)
    end
  end
end
