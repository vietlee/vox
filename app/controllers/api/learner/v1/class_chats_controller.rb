# Class group chats for the Vox Learner app. A learner sees one chat per class
# (learner_folder) they belong to. Real-time delivery is over ActionCable
# (ClassChatChannel); this controller handles list / history / send / read.
class Api::Learner::V1::ClassChatsController < Api::Learner::V1::BaseController
  before_action :set_folder, only: [:messages, :create, :mark_read, :content]

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
    body  = params[:body].to_s.strip
    files = Array(params[:files]).reject(&:blank?)
    if body.blank? && files.empty?
      return render json: { error: "Tin nhắn trống." }, status: :unprocessable_entity
    end
    msg = @folder.class_chat_messages.new(sender: current_learner, body: body)
    msg.files.attach(files) if files.any?
    msg.save!
    ClassChatRead.touch_for!(@folder, current_learner)
    render json: { message: msg.as_chat_json }
  end

  # POST /api/learner/v1/class_chats/:id/read
  def mark_read
    ClassChatRead.touch_for!(@folder, current_learner)
    render json: { ok: true }
  end

  # GET /api/learner/v1/class_chats/unread_count
  # Lightweight aggregate for the Messenger-style badge on the "Lớp học" nav
  # item: total unread across every class the learner belongs to, plus whether
  # they belong to any class at all (drives showing the tab).
  def unread_count
    folders = current_learner.learner_folders.to_a
    total = folders.sum { |f| f.unread_count_for(current_learner) }
    render json: { count: total, has_classes: folders.any? }
  end

  # GET /api/learner/v1/class_chats/:id/content
  # The learner's quiz / flashcard / learning-path assignments made through this
  # class, so the app can show class content alongside the chat.
  def content
    quizzes = current_learner.quiz_assignments
                .where(learner_folder_id: @folder.id).includes(:quiz_set).order(created_at: :desc)
    flashcards = current_learner.flashcard_assignments
                .where(learner_folder_id: @folder.id).includes(:flashcard_deck).order(created_at: :desc)
    paths = current_learner.learning_path_assignments
                .where(learner_folder_id: @folder.id).includes(:learning_path).order(created_at: :desc)

    render json: {
      quizzes:    quizzes.map { |a| { token: a.token, title: a.quiz_set&.title, status: a.status, due_at: a.due_at&.iso8601 } },
      flashcards: flashcards.map { |a| { token: a.token, title: a.flashcard_deck&.title, status: a.status } },
      paths:      paths.map { |a| { token: a.token, title: a.learning_path&.title, status: a.status } }
    }
  end

  private

  def set_folder
    @folder = LearnerFolder.find_by(id: params[:id])
    unless @folder && @folder.chat_member?(current_learner)
      render json: { error: "Bạn không thuộc lớp này." }, status: :forbidden
    end
  end
end
