class Admin::WorkspaceSettingsController < Admin::BaseController
  before_action :require_admin!

  def show
    @workspace = current_workspace
  end

  def update
    @workspace = current_workspace
    if @workspace.update(workspace_params)
      audit_log("workspace.settings_update", resource: @workspace)
      redirect_to workspace_settings_path, notice: t("settings.updated")
    else
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    workspace = current_workspace
    name = workspace.name
    workspace.purge!
    sign_out current_user
    redirect_to new_user_session_path,
      notice: I18n.locale == :vi ?
        "Workspace \"#{name}\" đã được xóa vĩnh viễn." :
        "Workspace \"#{name}\" has been permanently deleted."
  rescue => e
    Rails.logger.error "[WorkspacePurge] #{e.message}"
    redirect_to workspace_settings_path,
      alert: I18n.locale == :vi ? "Có lỗi khi xóa workspace. Vui lòng thử lại." : "Failed to delete workspace. Please try again."
  end

  private

  def workspace_params
    params.require(:workspace).permit(:name, :logo, :brand_color, :favicon, :language, :timezone, :force_2fa, :session_timeout_days, :custom_domain)
  end
end
