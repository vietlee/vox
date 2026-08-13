class LearnerFolder < ApplicationRecord
  belongs_to :workspace
  belongs_to :created_by, class_name: "User"
  has_many :learner_folder_members, dependent: :destroy
  has_many :learners, through: :learner_folder_members

  # Group chat (one per class).
  has_many :class_chat_messages, dependent: :destroy
  has_many :class_chat_reads,    dependent: :destroy

  # Tuition / finance
  has_many :tuition_payments, dependent: :destroy
  has_many :finance_entries,  dependent: :nullify
  enum :tuition_cycle, { monthly: 0, quarterly: 1 }, prefix: :cycle

  validates :name, presence: true

  # Create unpaid tuition records for every current member for [period_key]
  # (idempotent — skips members who already have one). Returns count created.
  def generate_tuition_roster!(period_key)
    created = 0
    learners.find_each do |l|
      rec = tuition_payments.find_or_initialize_by(learner_id: l.id, period_key: period_key)
      if rec.new_record?
        rec.workspace    = workspace
        rec.amount_cents = tuition_amount_cents
        rec.status       = :unpaid
        rec.save!
        created += 1
      end
    end
    created
  end

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
