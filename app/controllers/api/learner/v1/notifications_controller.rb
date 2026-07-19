class Api::Learner::V1::NotificationsController < Api::Learner::V1::BaseController
  def index
    notifications = current_learner.learner_notifications
                      .order(read: :asc, created_at: :desc).limit(50)
    render json: {
      notifications: notifications.map { |n|
        { id: n.id, title: n.title, body: n.body, read: n.read,
          created_at: n.created_at, kind: n.notification_type, action_url: n.action_url }
      },
      unread_count: current_learner.learner_notifications.unread.count
    }
  end

  def mark_all_read
    current_learner.learner_notifications.unread.update_all(read: true)
    render json: { ok: true }
  end

  def mark_read
    current_learner.learner_notifications.find_by(id: params[:id])&.update_column(:read, true)
    render json: { ok: true }
  end

  def unread_count
    render json: { count: current_learner.learner_notifications.unread.count }
  end
end
