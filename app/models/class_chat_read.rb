# Per-member read cursor for a class chat, used to compute unread counts.
# member is polymorphic (User teacher or Learner).
class ClassChatRead < ApplicationRecord
  belongs_to :learner_folder
  belongs_to :member, polymorphic: true

  # Move the read cursor to now (creating the row on first read).
  def self.touch_for!(learner_folder, member)
    rec = find_or_initialize_by(
      learner_folder_id: learner_folder.id,
      member_type: member.class.name, member_id: member.id
    )
    rec.last_read_at = Time.current
    rec.save!
    rec
  end
end
