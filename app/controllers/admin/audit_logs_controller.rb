class Admin::AuditLogsController < Admin::BaseController
  before_action :require_admin!

  def index
    logs = current_workspace.audit_logs.recent
    logs = logs.where(user_id: params[:user_id]) if params[:user_id].present?
    logs = logs.where("action LIKE ?", "%#{params[:action]}%") if params[:action].present?
    @pagy, @logs = pagy(logs, items: 30)
  end
end
