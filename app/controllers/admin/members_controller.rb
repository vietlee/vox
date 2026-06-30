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
    name   = params[:user][:name].to_s.strip
    emails = params[:user][:emails].to_s.split(",").map { |e| e.strip.downcase }.uniq.select(&:present?)

    if emails.empty?
      @member = User.new(name: name)
      @member.errors.add(:email, t("members.field_required"))
      return render :new, status: :unprocessable_entity
    end

    invited = 0
    errors  = []

    emails.each do |email|
      existing_user = User.find_by(email: email)

      if existing_user && current_workspace.workspace_memberships.active.exists?(user: existing_user)
        errors << "#{email}: #{t("members.already_member")}"
        next
      end

      if existing_user
        membership = current_workspace.workspace_memberships.find_or_initialize_by(user: existing_user)
        membership.update!(role: :supporter, status: :active)
        MemberMailer.workspace_added(existing_user, current_workspace).deliver_later
        audit_log("member.invite", resource: existing_user)
        invited += 1
      else
        password = SecureRandom.hex(8)
        user = User.new(
          name:                  name,
          email:                 email,
          workspace:             current_workspace,
          role:                  :supporter,
          password:              password,
          password_confirmation: password,
          must_change_password:  true,
          confirmed_at:          Time.current
        )
        user.skip_confirmation_notification!
        if user.save
          current_workspace.workspace_memberships.create!(user: user, role: :supporter)
          MemberMailer.invitation(user, password).deliver_later
          audit_log("member.invite", resource: user)
          invited += 1
        else
          errors << "#{email}: #{user.errors.full_messages.join(", ")}"
        end
      end
    end

    if errors.any? && invited == 0
      @member = User.new(name: name)
      @member.errors.add(:email, errors.join("; "))
      render :new, status: :unprocessable_entity
    elsif errors.any?
      redirect_to members_path, alert: "Mời #{invited} thành viên thành công. Lỗi: #{errors.join("; ")}"
    else
      redirect_to members_path, notice: invited == 1 ? t("members.invited") : "Đã mời #{invited} thành viên thành công."
    end
  end

  def destroy
    membership = current_workspace.workspace_memberships.find_by!(user_id: params[:id])
    user = membership.user
    membership.destroy!

    # Nếu workspace này là workspace chính của user → tạo workspace cá nhân mới
    if user.workspace_id == current_workspace.id
      adjectives = %w[Sáng Xanh Vàng Mới Nhanh Thông Minh Sáng Tạo Năng Động]
      nouns      = %w[Không Gian Góc Làm Việc Studio Hub Trạm Tổ Bàn]
      name = "#{adjectives.sample} #{nouns.sample} của #{user.name.split.first}"
      personal_ws = Workspace.create!(
        name:      name,
        owner:     user,
        status:    :active,
        plan_type: :free
      )
      user.update_columns(workspace_id: personal_ws.id)
    end

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
