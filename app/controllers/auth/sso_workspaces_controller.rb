class Auth::SsoWorkspacesController < ApplicationController
  skip_before_action :authenticate_user!
  layout false

  before_action :require_omniauth_session

  def new
    @omniauth_user = session[:omniauth_user]
    @free_limits   = PlanConfig.limits_for("free")
  end

  def create
    workspace_name = params[:workspace_name].to_s.strip
    if workspace_name.blank?
      flash.now[:alert] = I18n.locale == :vi ? "Tên workspace không được để trống." : "Workspace name is required."
      @omniauth_user = session[:omniauth_user]
      render :new, status: :unprocessable_entity and return
    end

    omniauth_data = session[:omniauth_user]
    user = User.find_by(provider: omniauth_data["provider"], uid: omniauth_data["uid"])
    user ||= User.find_by(email: omniauth_data["email"])
    workspace = nil

    ActiveRecord::Base.transaction do
      unless user
        user = User.new(
          provider:     omniauth_data["provider"],
          uid:          omniauth_data["uid"],
          email:        omniauth_data["email"],
          name:         omniauth_data["name"],
          password:     Devise.friendly_token[0, 20],
          confirmed_at: Time.current,
          role:         :admin
        )
      end

      user.save! unless user.persisted?
      workspace = Workspace.new(name: workspace_name, status: :active, owner: user)
      workspace.save!
      user.update_columns(workspace_id: workspace.id)

      workspace.subscriptions.create!(
        plan:           :free,
        status:         :active,
        starts_at:      Time.current,
        credit_balance: 0,
        max_ai_credits: 0
      )
    end

    session.delete(:omniauth_user)
    sign_in(:user, user)
    WorkspaceMailer.new_workspace_alert(workspace, user).deliver_later if workspace

    notice_msg = I18n.locale == :vi ?
      "Chào mừng! Workspace \"#{workspace_name}\" đã được tạo." :
      "Welcome! Workspace \"#{workspace_name}\" has been created."
    pending_id = consume_pending_template_id
    if pending_id
      redirect_to use_template_path(pending_id), notice: notice_msg
    else
      redirect_to dashboard_path, notice: notice_msg
    end

  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.record.errors.full_messages.first
    @omniauth_user = session[:omniauth_user]
    @free_limits   = PlanConfig.limits_for("free")
    render :new, status: :unprocessable_entity
  end

  private

  def require_omniauth_session
    unless session[:omniauth_user].present?
      redirect_to new_user_session_path
    end
  end
end
