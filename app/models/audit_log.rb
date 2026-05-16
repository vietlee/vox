class AuditLog < ApplicationRecord
  belongs_to :workspace, optional: true
  belongs_to :user, optional: true

  validates :action, presence: true

  scope :recent, -> { order(created_at: :desc) }

  def self.record(user:, action:, resource: nil, changes: {}, request: nil)
    create!(
      workspace:     user&.workspace,
      user:          user,
      action:        action,
      resource_type: resource&.class&.name,
      resource_id:   resource&.id,
      changes_data:  changes,
      ip_address:    request&.remote_ip,
      user_agent:    request&.user_agent
    )
  end
end
