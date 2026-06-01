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

  def prevent_duplicate_response
    return if survey.nil?
    return unless survey.max_per_user.to_i > 0

    completed = survey.responses.completed

    # 1. Strongest: user_id (logged-in, cross-device)
    if user_id.present? && completed.exists?(user_id: user_id)
      errors.add(:base, :already_responded) and return
    end

    # 2. Cookie token (anonymous, same browser)
    if respondent_token.present? && completed.exists?(respondent_token: respondent_token)
      errors.add(:base, :already_responded) and return
    end

    # 3. Email match
    if respondent_email.present? && completed.exists?(respondent_email: respondent_email)
      errors.add(:base, :already_responded) and return
    end

    # 4. IP-based (anonymous users who cleared cookies) — only for anonymous surveys
    if respondent_ip.present? && survey.anonymous? && completed.where.not(respondent_ip: nil).exists?(respondent_ip: respondent_ip)
      errors.add(:base, :already_responded)
    end
  end
end
