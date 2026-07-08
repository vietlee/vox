class Learner::NotificationsController < Learner::BaseController
  def index
    @notifications = current_learner.learner_notifications.recent.limit(50)
    current_learner.learner_notifications.unread.update_all(read: true)
  end

  def mark_read
    current_learner.learner_notifications.find_by(id: params[:id])&.update_column(:read, true)
    render json: { ok: true }
  end

  def unread_count
    render json: { count: current_learner.learner_notifications.unread.count }
  end
end
