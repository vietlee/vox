class AuditLog < ApplicationRecord
  belongs_to :workspace, optional: true
  belongs_to :user, optional: true

  validates :action, presence: true

  scope :recent, -> { order(created_at: :desc) }

  ACTION_ICONS = {
    "survey"         => "📋",
    "vote"           => "🗳️",
    "feedback_board" => "💬",
    "member"         => "👤",
    "workspace"      => "⚙️",
  }.freeze

  ACTION_COLORS = {
    "survey.create"            => "indigo",
    "survey.update"            => "slate",
    "survey.publish"           => "emerald",
    "survey.close"             => "amber",
    "survey.archive"           => "slate",
    "survey.clone"             => "violet",
    "vote.create"              => "blue",
    "vote.open"                => "emerald",
    "vote.close"               => "amber",
    "feedback_board.create"    => "teal",
    "feedback_board.update"    => "slate",
    "feedback_board.close"     => "amber",
    "member.invite"            => "purple",
    "member.reset_password"    => "orange",
    "member.remove"            => "red",
    "workspace.settings_update"=> "slate",
  }.freeze

  def action_icon
    category = action.to_s.split(".").first
    ACTION_ICONS[category] || "🔹"
  end

  def action_color
    ACTION_COLORS[action.to_s] || "slate"
  end

  def human_action
    category, verb = action.to_s.split(".", 2)
    I18n.t("audit_log.actions.#{category}.#{verb}", default: action.to_s)
  end

  def resource_name
    return nil unless resource_type.present? && resource_id.present?
    klass = resource_type.constantize rescue nil
    return nil unless klass
    record = klass.find_by(id: resource_id)
    record&.try(:title) || record&.try(:name) || record&.try(:email) || "##{resource_id}"
  rescue
    "##{resource_id}"
  end

  def self.record(user:, action:, workspace: nil, resource: nil, changes: {}, request: nil)
    create!(
      workspace:     workspace || user&.workspace,
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
