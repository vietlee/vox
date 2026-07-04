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
      # Only create subscription if user has none yet (first workspace).
      # Additional workspaces share the same user budget via credit_subscription → owner.subscription.
      unless current_user.subscription.present?
        workspace.subscriptions.create!(
          user_id:        current_user.id,
          plan:           :free,
          status:         :active,
          starts_at:      Time.current,
          credit_balance: Subscription.monthly_free_credits,
          max_ai_credits: Subscription.monthly_free_credits
        )
      end
    end

    session[:current_workspace_id] = workspace.id
    @accessible_workspaces = nil  # reset cache

    msg = I18n.locale == :vi ? "Đã tạo \"#{workspace.name}\"!" : "\"#{workspace.name}\" created!"
    redirect_to dashboard_path, notice: msg
  end
end
