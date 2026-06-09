class Response < ApplicationRecord
  belongs_to :survey
  belongs_to :workspace
  has_many   :answers, dependent: :destroy

  enum :status, { in_progress: 0, completed: 1 }

  validates :survey, :workspace, presence: true

  scope :completed, -> { where(status: :completed) }
  scope :quality,   -> { where(excluded: false) }

  after_create :increment_survey_counter

  def complete!(time_seconds = nil)
    update!(
      status: :completed,
      completed_at: Time.current,
      completion_time_seconds: time_seconds.present? ? time_seconds.to_i : (Time.current - created_at).to_i
    )
    survey.increment!(:response_count)
    notify_admins_of_new_response
  end

  private

  def notify_admins_of_new_response
    return unless workspace.notify_on_new_response?
    workspace.admin_users.each do |admin|
      NotificationMailer.new_response(self, admin).deliver_later
    end
  end

  def increment_survey_counter
    # response_count will be incremented on complete!
  end

end
