class Admin::WorkspaceSettingsController < Admin::BaseController
  before_action :require_admin!

  def show
    @workspace = current_workspace
    @is_last_owned_workspace = current_user.owned_workspaces.count <= 1
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

    # Resolve other workspace BEFORE purging — purge! deletes users with workspace_id = wid,
    # which would delete current_user if their workspace_id still points here.
    other = current_user.owned_workspaces.where.not(id: workspace.id).order(:id).first

    if other
      # Move current_user out of the workspace being deleted so purge! doesn't delete them
      current_user.update_column(:workspace_id, other.id)
    end

    workspace.purge!

    if other
      session[:current_workspace_id] = other.id
      redirect_to dashboard_path,
        notice: I18n.locale == :vi ?
          "Workspace \"#{name}\" đã được xóa. Đã chuyển sang \"#{other.name}\"." :
          "Workspace \"#{name}\" deleted. Switched to \"#{other.name}\"."
    else
      sign_out current_user
      redirect_to new_user_session_path,
        notice: I18n.locale == :vi ?
          "Workspace \"#{name}\" đã được xóa vĩnh viễn." :
          "Workspace \"#{name}\" has been permanently deleted."
    end
  rescue => e
    Rails.logger.error "[WorkspacePurge] #{e.message}"
    redirect_to workspace_settings_path,
      alert: I18n.locale == :vi ? "Có lỗi khi xóa workspace. Vui lòng thử lại." : "Failed to delete workspace. Please try again."
  end

  private

  def workspace_params
    params.require(:workspace).permit(:name, :logo, :brand_color, :favicon, :language, :timezone, :force_2fa, :session_timeout_days, :custom_domain, :notify_on_new_feedback, :notify_on_new_response)
  end
end
