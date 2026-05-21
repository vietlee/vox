class SuperAdmin::WorkspacesController < SuperAdmin::BaseController
  before_action :set_workspace, only: [:show, :edit, :update, :destroy, :activate, :suspend, :reset_admin_password]

  def index
    @pagy, @workspaces = pagy(Workspace.order(created_at: :desc), items: 20)
  end

  def new
    @workspace = Workspace.new
  end

  def create
    @workspace = Workspace.new(workspace_params)
    admin_email = params[:admin_email]
    admin_name  = params[:admin_name]

    if @workspace.save
      password = SecureRandom.hex(8)
      admin = @workspace.users.create!(
        name: admin_name,
        email: admin_email,
        role: :admin,
        password: password,
        password_confirmation: password,
        must_change_password: true
      )
      subscription = @workspace.subscriptions.create!(plan: params[:plan] || :free, status: :active, credit_balance: Subscription::PLAN_LIMITS[params[:plan] || "free"][:max_ai_credits].to_i)

      WorkspaceMailer.welcome(admin, password, @workspace).deliver_later
      redirect_to super_admin_workspaces_path, notice: "Workspace created and admin invited."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  def edit
  end

  def update
    if @workspace.update(workspace_params)
      redirect_to super_admin_workspaces_path, notice: "Workspace updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @workspace.name
    @workspace.purge!
    redirect_to super_admin_workspaces_path,
      notice: "Workspace \"#{name}\" đã được xóa vĩnh viễn."
  rescue => e
    Rails.logger.error "[WorkspacePurge] #{e.message}"
    redirect_to super_admin_workspaces_path, alert: "Lỗi khi xóa: #{e.message}"
  end

  def activate
    @workspace.update!(status: :active)
    redirect_to super_admin_workspaces_path
  end

  def suspend
    @workspace.update!(status: :suspended)
    redirect_to super_admin_workspaces_path
  end

  def reset_admin_password
    admin = @workspace.admin_users.first
    new_password = SecureRandom.hex(8)
    admin.update!(password: new_password, password_confirmation: new_password, must_change_password: true)
    MemberMailer.password_reset(admin, new_password).deliver_later
    redirect_to super_admin_workspaces_path, notice: "Password reset and emailed."
  end

  private

  def set_workspace
    @workspace = Workspace.find(params[:id])
  end

  def workspace_params
    params.require(:workspace).permit(:name, :slug, :logo, :brand_color, :language, :timezone, :status)
  end
end
