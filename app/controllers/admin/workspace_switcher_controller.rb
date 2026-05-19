class Admin::WorkspaceSwitcherController < Admin::BaseController
  # Skip workspace checks — user is switching, not acting inside a workspace
  skip_before_action :require_workspace_member!
  skip_before_action :require_workspace_active!

  def switch
    ws_id = params[:workspace_id].to_i
    target = accessible_workspaces.find { |w| w.id == ws_id }

    if target.nil?
      redirect_to dashboard_path and return
    end

    unless target.active?
      redirect_to dashboard_path, alert: t("workspace.suspended_cannot_switch", name: target.name) and return
    end

    session[:current_workspace_id] = ws_id
    redirect_to dashboard_path
  end
end
