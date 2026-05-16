class Admin::NotificationsController < Admin::BaseController
  def index
    @pagy, @notifications = pagy(current_user.notifications.recent, items: 20)
  end

  def mark_read
    current_user.notifications.find(params[:id]).update!(read: true)
    head :ok
  end

  def mark_all_read
    current_user.notifications.unread.update_all(read: true)
    head :ok
  end
end
