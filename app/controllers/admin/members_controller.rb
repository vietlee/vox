class Admin::MembersController < Admin::BaseController
  before_action :require_admin!

  def index
    @members = current_workspace.workspace_memberships
                                .includes(:user)
                                .where(status: :active)
                                .order(created_at: :desc)
  end

  def new
    @member = User.new
  end

  def create
    email = params[:user][:email].to_s.strip.downcase
    name  = params[:user][:name].to_s.strip

    # Check supporter limit against subscription
    sub = current_workspace.current_subscription
    if sub && !sub.within_supporter_limit?
      @member = User.new(email: email, name: name)
      @member.errors.add(:base, t("members.supporter_limit_reached"))
      return render :new, status: :unprocessable_entity
    end

    # Check if already an ACTIVE member of this workspace
    existing_user = User.find_by(email: email)
    if existing_user && current_workspace.workspace_memberships.active.exists?(user: existing_user)
      @member = User.new(email: email, name: name)
      @member.errors.add(:email, t("members.already_member"))
      return render :new, status: :unprocessable_entity
    end

    if existing_user
      # User exists globally — restore or create membership
      membership = current_workspace.workspace_memberships.find_or_initialize_by(user: existing_user)
      membership.update!(role: :supporter, status: :active)
      MemberMailer.workspace_added(existing_user, current_workspace).deliver_later
      audit_log("member.invite", resource: existing_user)
      redirect_to members_path, notice: t("members.invited")
    else
      # New user — create account then membership
      password = SecureRandom.hex(8)
      @member = User.new(
        name:                  name,
        email:                 email,
        workspace:             current_workspace,
        role:                  :supporter,
        password:              password,
        password_confirmation: password,
        must_change_password:  true,
        confirmed_at:          Time.current
      )
      @member.skip_confirmation_notification!

      if @member.save
        current_workspace.workspace_memberships.create!(user: @member, role: :supporter)
        MemberMailer.invitation(@member, password).deliver_later
        audit_log("member.invite", resource: @member)
        redirect_to members_path, notice: t("members.invited")
      else
        render :new, status: :unprocessable_entity
      end
    end
  end

  def destroy
    membership = current_workspace.workspace_memberships.find_by!(user_id: params[:id])
    membership.destroy!
    redirect_to members_path, notice: t("members.deactivated")
  end

  def toggle_status
    membership = current_workspace.workspace_memberships.find_by!(user_id: params[:id])
    membership.update!(status: membership.active? ? :inactive : :active)
    redirect_to members_path
  end

  def reset_password
    member = current_workspace.users.find(params[:id])
    new_password = SecureRandom.hex(8)
    member.update!(
      password:              new_password,
      password_confirmation: new_password,
      must_change_password:  true
    )
    MemberMailer.password_reset(member, new_password).deliver_later
    audit_log("member.reset_password", resource: member)
    redirect_to members_path, notice: t("members.password_reset_sent", email: member.email)
  end
end
