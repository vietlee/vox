class Admin::WorkspaceSettingsController < Admin::BaseController
  before_action :require_admin!

  def show
    @workspace = current_workspace
  end

  def update
    @workspace = current_workspace
    if @workspace.update(workspace_params)
      AuditLog.record(user: current_user, action: "workspace.settings_update", resource: @workspace)
      redirect_to workspace_settings_path, notice: t("settings.updated")
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def workspace_params
    params.require(:workspace).permit(:name, :logo, :brand_color, :favicon, :language, :timezone, :force_2fa, :session_timeout_days, :custom_domain)
  end
end
