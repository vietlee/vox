class Response < ApplicationRecord
  belongs_to :survey
  belongs_to :workspace
  has_many   :answers, dependent: :destroy

  enum :status, { in_progress: 0, completed: 1 }

  validates :survey, :workspace, presence: true

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
end
