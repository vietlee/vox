class SuperAdmin::SubscriptionsController < SuperAdmin::BaseController
  before_action :set_subscription, only: [:show, :edit, :update]

  def index
    scope = Subscription.active.includes(:workspace).order(created_at: :desc)
    @pagy, @subscriptions = pagy(scope, items: 25)
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
