class LearnerFolder < ApplicationRecord
  belongs_to :workspace
  belongs_to :created_by, class_name: "User"
  has_many :learner_folder_members, dependent: :destroy
  has_many :learners, through: :learner_folder_members

  # Group chat (one per class).
  has_many :class_chat_messages, dependent: :destroy
  has_many :class_chat_reads,    dependent: :destroy

  validates :name, presence: true

  def member_count
    learner_folder_members.count
  end

  # ── Chat access control ──────────────────────────────────────────────
  # A learner belongs to the chat if they're in this class; a teacher (User)
  # belongs if they can access this class's workspace.
  def chat_member?(actor)
    case actor
    when Learner then learners.exists?(actor.id)
    when User    then accessible_by_user?(actor)
    else false
    end
  end

  def accessible_by_user?(user)
    return false unless user
    user.super_admin? ||
      workspace&.owner_id == user.id ||
      user.workspace_id == workspace_id ||
      user.workspace_memberships.exists?(workspace_id: workspace_id)
  end

  # Unread message count for a member (User or Learner).
  def unread_count_for(member)
    read = class_chat_reads.find_by(member_type: member.class.name, member_id: member.id)
    scope = class_chat_messages
    scope = scope.where("created_at > ?", read.last_read_at) if read
    # Don't count the member's own messages as unread.
    scope.where.not(sender_type: member.class.name, sender_id: member.id).count
  end
end
