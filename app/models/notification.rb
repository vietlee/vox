class Notification < ApplicationRecord
  belongs_to :workspace
  belongs_to :user

  TYPES = %w[
    workspace_created supporter_invited survey_new feedback_new_pending
    subscription_expiring payment_success survey_submitted ai_job_done
    ai_credits_low monthly_digest anomaly_detected system_broadcast
    learning_path_assigned
  ].freeze

  validates :notification_type, inclusion: { in: TYPES }
  validates :title, presence: true

  scope :unread,  -> { where(read: false) }
  scope :recent,  -> { order(created_at: :desc) }

  after_create_commit :broadcast_to_user

  def self.broadcast_to_workspace(workspace:, title:, body: nil)
    workspace.users.where(role: :admin).each do |admin|
      create!(
        workspace:         workspace,
        user:              admin,
        notification_type: "system_broadcast",
        title:             title,
        body:              body
      )
    end
  end

  def self.notify(user:, type:, title:, body: nil, resource: nil, metadata: {})
    create!(
      workspace:         user.workspace,
      user:              user,
      notification_type: type,
      title:             title,
      body:              body,
      resource_type:     resource&.class&.name,
      resource_id:       resource&.id,
      metadata:          metadata
    )
  end

  private

  def broadcast_to_user
    ActionCable.server.broadcast("user_#{user_id}", {
      type: "notification",
      id: id,
      title: title,
      body: body
    })
  end
end
