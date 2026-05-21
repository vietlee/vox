class Admin::BaseController < ApplicationController
  before_action :require_workspace_member!
  before_action :require_workspace_active!
  layout "admin"

  private

  def require_workspace_member!
    # Participant users cannot access admin dashboard
    if current_user&.participant?
      redirect_to my_participations_path, alert: t("errors.access_denied")
      return
    end
    unless current_workspace_role.present?
      redirect_to new_user_session_path, alert: t("errors.access_denied")
    end
  end

  def require_workspace_active!
    return if current_workspace.nil?
    unless current_workspace.active?
      sign_out current_user
      redirect_to new_user_session_path, alert: t("errors.workspace_suspended")
    end
  end

  def audit_log(action, resource: nil, changes: {})
    AuditLog.record(
      user:      current_user,
      workspace: current_workspace,
      action:    action,
      resource:  resource,
      changes:   changes,
      request:   request
    )
  end

  def require_admin!
    unless current_workspace_admin?
      redirect_to dashboard_path, alert: t("errors.admin_only")
    end
  end

  # Simple pagination helper
  def pagy(scope, items: 15)
    page  = (params[:page] || 1).to_i
    total = scope.count
    records = scope.offset((page - 1) * items).limit(items)
    pagy_obj = Struct.new(:page, :items, :count, :pages).new(page, items, total, (total.to_f / items).ceil)
    [pagy_obj, records]
  end
end
