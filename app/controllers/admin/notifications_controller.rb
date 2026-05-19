class Admin::NotificationsController < Admin::BaseController
  def index
    @pagy, @notifications = pagy(current_user.notifications.recent, items: 20)
  end

  def mark_read
    current_user.notifications.find(params[:id]).update!(read: true)
    respond_to do |format|
      format.json { head :ok }
      format.html { redirect_to notifications_path }
    end
  end

  def mark_all_read
    current_user.notifications.unread.update_all(read: true)
    redirect_to notifications_path
  end
end
