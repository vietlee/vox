class MemberMailer < ApplicationMailer
  def invitation(user, password)
    @user     = user
    @password = password
    mail(to: user.email, subject: "You've been invited to Vox")
  end

  def workspace_added(user, workspace)
    @user      = user
    @workspace = workspace
    mail(to: user.email, subject: "Bạn được thêm vào workspace #{workspace.name} trên Vox")
  end

  def password_reset(user, password)
    @user     = user
    @password = password
    mail(to: user.email, subject: "Your Vox password has been reset")
  end
end
