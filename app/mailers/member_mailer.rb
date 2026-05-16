class MemberMailer < ApplicationMailer
  def invitation(user, password)
    @user     = user
    @password = password
    mail(to: user.email, subject: "You've been invited to Vox")
  end

  def password_reset(user, password)
    @user     = user
    @password = password
    mail(to: user.email, subject: "Your Vox password has been reset")
  end
end
