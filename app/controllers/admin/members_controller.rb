class Admin::MembersController < Admin::BaseController
  before_action :require_admin!

  def index
    @members = current_workspace.users.where(role: :supporter).order(created_at: :desc)
  end

  def new
    @member = User.new
  end

  def create
    password = SecureRandom.hex(8)
    @member = current_workspace.users.build(
      name: params[:user][:name],
      email: params[:user][:email],
      role: :supporter,
      password: password,
      password_confirmation: password,
      must_change_password: true
    )

    if @member.save
      MemberMailer.invitation(@member, password).deliver_later
      AuditLog.record(user: current_user, action: "member.invite", resource: @member)
      redirect_to members_path, notice: t("members.invited")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    member = current_workspace.users.find(params[:id])
    member.update!(status: :inactive)
    redirect_to members_path, notice: t("members.deactivated")
  end

  def toggle_status
    member = current_workspace.users.find(params[:id])
    member.update!(status: member.active? ? :inactive : :active)
    redirect_to members_path
  end
end
