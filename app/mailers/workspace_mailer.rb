class WorkspaceMailer < ApplicationMailer
  def welcome(admin, password, workspace)
    @admin     = admin
    @password  = password
    @workspace = workspace
    mail(to: admin.email, subject: "Welcome to #{workspace.name} on Vox!")
  end

  def new_workspace_alert(workspace, admin_user)
    @workspace  = workspace
    @admin_user = admin_user
    @app_host   = ENV.fetch("APP_HOST", "localhost:3000")
    @protocol   = ENV["APP_HOST"].present? ? "https" : "http"

    super_admin_emails = User.where(role: :super_admin).pluck(:email)
    return if super_admin_emails.empty?

    mail(
      to:      super_admin_emails,
      subject: "[VOX] Workspace mới: #{workspace.name}"
    )
  end
end
