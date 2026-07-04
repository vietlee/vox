class Admin::WorkspacesController < Admin::BaseController
  skip_before_action :require_workspace_member!
  skip_before_action :require_workspace_active!

  def new
  end

  def create
    name = params[:workspace_name].to_s.strip
    if name.blank?
      flash.now[:alert] = I18n.locale == :vi ? "Tên không được để trống." : "Name is required."
      render :new, status: :unprocessable_entity and return
    end

    workspace = Workspace.new(name: name, status: :active, owner: current_user)
    ActiveRecord::Base.transaction do
      workspace.save!
      # New workspaces do NOT get fresh credits — credits are per-user (primary workspace).
      # credit_subscription always resolves to owner.primary_subscription for billing.
      workspace.subscriptions.create!(
        plan:           :free,
        status:         :active,
        starts_at:      Time.current,
        credit_balance: 0,
        max_ai_credits: 0
      )
    end

    session[:current_workspace_id] = workspace.id
    @accessible_workspaces = nil  # reset cache

    msg = I18n.locale == :vi ? "Đã tạo \"#{workspace.name}\"!" : "\"#{workspace.name}\" created!"
    redirect_to dashboard_path, notice: msg
  end
end
