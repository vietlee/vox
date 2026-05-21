class Auth::RegistrationsController < Devise::RegistrationsController
  skip_before_action :require_no_authentication, only: []
  layout false

  def new
    @user = User.new
    @free_limits = PlanConfig.limits_for("free")
  end

  def create
    workspace_name = params[:workspace_name].to_s.strip
    if workspace_name.blank?
      flash.now[:alert] = "Tên workspace không được để trống."
      @user = User.new(user_params)
      render :new, status: :unprocessable_entity and return
    end

    @user = User.new(user_params)
    @user.role = :admin
    @user.confirmed_at = Time.current  # auto-confirm

    workspace = Workspace.new(name: workspace_name, status: :active)

    ActiveRecord::Base.transaction do
      workspace.save!
      @user.workspace = workspace
      @user.save!

      free_limits = PlanConfig.limits_for("free").transform_values { |v| v || 0 }
      workspace.subscriptions.create!(
        plan:           :free,
        status:         :active,
        starts_at:      Time.current,
        ends_at:        nil,
        credit_balance: free_limits[:max_ai_credits].to_i,
        features:       PlanConfig.features_for("free"),
        **free_limits
      )
    end

    sign_in(:user, @user)
    redirect_to dashboard_path, notice: "Chào mừng! Workspace \"#{workspace.name}\" đã được tạo."
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.record.errors.full_messages.first
    render :new, status: :unprocessable_entity
  end

  private

  def user_params
    p = params.permit(:name, :email, :password, :password_confirmation)
    # If name not provided, use email prefix as name
    p[:name] = p[:email].to_s.split("@").first if p[:name].blank?
    p
  end
end
