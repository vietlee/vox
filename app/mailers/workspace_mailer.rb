class WorkspaceMailer < ApplicationMailer
  def welcome(admin, password, workspace)
    @admin     = admin
    @password  = password
    @workspace = workspace
    mail(to: admin.email, subject: "Welcome to #{workspace.name} on Vox!")
  end
end
