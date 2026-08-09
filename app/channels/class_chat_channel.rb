# Real-time delivery for a single class group chat. Both the teacher web admin
# and the learner app subscribe with { folder_id: }. Only members of that class
# (the teacher who owns the workspace, or a learner enrolled in it) are allowed.
#
# Messages are *sent* via HTTP POST (web + app); the model's after_create_commit
# broadcasts them to this stream, so this channel is receive-only.
class ClassChatChannel < ApplicationCable::Channel
  def subscribed
    folder = LearnerFolder.find_by(id: params[:folder_id])
    if folder && current_actor && folder.chat_member?(current_actor)
      stream_from ClassChatMessage.stream_for(folder.id)
    else
      reject
    end
  end

  def unsubscribed; end

  private

  def current_actor
    current_user || current_learner
  end
end
