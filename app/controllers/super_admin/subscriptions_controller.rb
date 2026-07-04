class SuperAdmin::SubscriptionsController < SuperAdmin::BaseController
  before_action :set_subscription, only: [:show, :edit, :update]

  def index
    # List per-user: each workspace owner with their primary subscription
    @user_subs = User
      .joins("INNER JOIN workspaces ON workspaces.owner_id = users.id")
      .select("users.id, users.name, users.email,
               MIN(workspaces.id) AS primary_workspace_id,
               COUNT(DISTINCT workspaces.id) AS workspace_count")
      .group("users.id, users.name, users.email")
      .order("users.id ASC")

    primary_ws_ids = @user_subs.map(&:primary_workspace_id).compact
    @primary_subs  = Subscription.where(workspace_id: primary_ws_ids, status: :active)
                                  .order(created_at: :desc)
                                  .index_by(&:workspace_id)
  end

  def show
    @payments = @subscription.payments.order(created_at: :desc).limit(20)
  end

  def edit; end

  def update
    if @subscription.update(subscription_params)
      redirect_to super_admin_subscription_path(@subscription), notice: "Cập nhật subscription thành công."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_subscription
    @subscription = Subscription.includes(:workspace).find(params[:id])
  end

  def subscription_params
    params.require(:subscription).permit(:credit_balance, :max_ai_credits)
  end
end
