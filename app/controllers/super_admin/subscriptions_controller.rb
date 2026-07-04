class SuperAdmin::SubscriptionsController < SuperAdmin::BaseController
  before_action :set_subscription, only: [:show, :edit, :update]

  def index
    # Load all users who own at least one workspace, with their workspaces eager-loaded
    @owners = User
      .joins("INNER JOIN workspaces ON workspaces.owner_id = users.id")
      .where.not(workspaces: { id: nil })
      .distinct
      .order("users.id ASC")
      .includes(:owned_workspaces)

    # For each owner, load their subscription directly via user_id
    @primary_subs = {}
    @owners.each do |user|
      @primary_subs[user.id] = user.subscription
    end
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
    @subscription = Subscription.includes(:workspace, :user).find(params[:id])
    @subscription_user = @subscription.user || @subscription.workspace&.owner
  end

  def subscription_params
    params.require(:subscription).permit(:credit_balance, :max_ai_credits)
  end
end
