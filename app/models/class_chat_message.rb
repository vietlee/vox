# A single message in a class group chat. One chat per class (learner_folder);
# the sender is polymorphic so both teachers (User) and learners (Learner) can
# post in the same thread.
class ClassChatMessage < ApplicationRecord
  belongs_to :learner_folder
  belongs_to :sender, polymorphic: true

  validates :body, presence: true, length: { maximum: 5000 }

  after_create_commit :broadcast_message

  # Stream name shared by the web (admin) and app (learner) ActionCable clients.
  def self.stream_for(learner_folder_id)
    "class_chat_#{learner_folder_id}"
  end

  def sender_role
    sender_type == "User" ? "teacher" : "learner"
  end

  def sender_name
    sender&.name.presence || (sender_role == "teacher" ? "Giáo viên" : "Học viên")
  end

  def as_chat_json
    {
      id:          id,
      body:        body,
      sender_role: sender_role,
      sender_type: sender_type,
      sender_id:   sender_id,
      sender_name: sender_name,
      created_at:  created_at.iso8601
    }
  end

  private

  def broadcast_message
    ActionCable.server.broadcast(
      self.class.stream_for(learner_folder_id),
      { type: "new_message", message: as_chat_json }
    )
  end
end
