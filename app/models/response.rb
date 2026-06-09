class Response < ApplicationRecord
  belongs_to :survey
  belongs_to :workspace
  has_many   :answers, dependent: :destroy

  enum :status, { in_progress: 0, completed: 1 }

  validates :survey, :workspace, presence: true

  scope :completed, -> { where(status: :completed) }
  scope :quality,   -> { where(excluded: false) }

  after_create :increment_survey_counter
  before_create :generate_edit_token_if_needed

  MAX_COMPLETION_SECONDS = 30.minutes.to_i  # cap idle sessions

  def complete!(time_seconds = nil)
    raw = time_seconds.present? ? time_seconds.to_i : (Time.current - created_at).to_i
    update!(
      status: :completed,
      completed_at: Time.current,
      completion_time_seconds: [raw, MAX_COMPLETION_SECONDS].min
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

  def generate_edit_token_if_needed
    # Generate token whenever allow_edit is on AND we'll have a recipient email
    # (email_required mode OR login_required/SSO — email resolved at controller level)
    return unless survey&.allow_edit?
    return unless survey&.email_required? || survey&.login_required?
    self.edit_token = SecureRandom.urlsafe_base64(24)
  end

end
