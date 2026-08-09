# Class group chats for the Vox Learner app. A learner sees one chat per class
# (learner_folder) they belong to. Real-time delivery is over ActionCable
# (ClassChatChannel); this controller handles list / history / send / read.
class Api::Learner::V1::ClassChatsController < Api::Learner::V1::BaseController
  before_action :set_folder, only: [:messages, :create, :mark_read]

  # GET /api/learner/v1/class_chats
  # List the learner's classes with a preview + unread count.
  def index
    folders = current_learner.learner_folders.includes(:workspace).order(:name)
    render json: {
      classes: folders.map { |f|
        last = f.class_chat_messages.order(created_at: :desc).first
        {
          id:           f.id,
          name:         f.name,
          member_count: f.member_count,
          unread:       f.unread_count_for(current_learner),
          last_message: last&.as_chat_json
        }
      }
    }
  end

  # GET /api/learner/v1/class_chats/:id/messages
  def messages
    msgs = @folder.class_chat_messages.order(created_at: :asc).last(200)
    ClassChatRead.touch_for!(@folder, current_learner)
    render json: {
      messages: msgs.map(&:as_chat_json),
      me: { type: "Learner", id: current_learner.id, name: current_learner.name },
      class: { id: @folder.id, name: @folder.name }
    }
  end

  # POST /api/learner/v1/class_chats/:id/messages  { body: }
  def create
    body = params[:body].to_s.strip
    if body.blank?
      return render json: { error: "Tin nhắn trống." }, status: :unprocessable_entity
    end
    msg = @folder.class_chat_messages.create!(sender: current_learner, body: body)
    ClassChatRead.touch_for!(@folder, current_learner)
    render json: { message: msg.as_chat_json }
  end

  # POST /api/learner/v1/class_chats/:id/read
  def mark_read
    ClassChatRead.touch_for!(@folder, current_learner)
    render json: { ok: true }
  end

  private

  def set_folder
    @folder = LearnerFolder.find_by(id: params[:id])
    unless @folder && @folder.chat_member?(current_learner)
      render json: { error: "Bạn không thuộc lớp này." }, status: :forbidden
    end
  end
end
