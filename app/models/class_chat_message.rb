# A single message in a class group chat. One chat per class (learner_folder);
# the sender is polymorphic so both teachers (User) and learners (Learner) can
# post in the same thread. A message carries text and/or attachments (images,
# documents, voice notes).
class ClassChatMessage < ApplicationRecord
  belongs_to :learner_folder
  belongs_to :sender, polymorphic: true

  has_many_attached :files

  validates :body, length: { maximum: 5000 }
  validate  :body_or_attachment_present

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
      created_at:  created_at.iso8601,
      attachments: files.map { |f| attachment_json(f) }
    }
  end

  private

  ASSET_HOST = { host: ENV.fetch("APP_HOST", "vox.czin.net"), protocol: "https" }.freeze

  def attachment_json(file)
    ct = file.content_type.to_s
    kind = if ct.start_with?("image/") then "image"
           elsif ct.start_with?("audio/") then "audio"
           else "file"
           end
    {
      url:          Rails.application.routes.url_helpers.rails_blob_url(file, ASSET_HOST),
      filename:     file.filename.to_s,
      content_type: ct,
      byte_size:    file.byte_size,
      kind:         kind
    }
  rescue => e
    Rails.logger.warn "[ClassChat attachment_json] #{e.message}"
    nil
  end

  def body_or_attachment_present
    if body.blank? && !files.attached?
      errors.add(:base, "Tin nhắn phải có nội dung hoặc tệp đính kèm.")
    end
  end

  def broadcast_message
    ActionCable.server.broadcast(
      self.class.stream_for(learner_folder_id),
      { type: "new_message", message: as_chat_json }
    )
  end
end
