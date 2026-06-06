class SuperAdmin::SubscriptionsController < SuperAdmin::BaseController
  before_action :set_subscription, only: [:show, :edit, :update]

  def index
    scope = Subscription.includes(:workspace).order(created_at: :desc)
    scope = scope.where(plan: params[:plan])     if params[:plan].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    @pagy, @subscriptions = pagy(scope, items: 25)
  end

  def show
    @payments = @subscription.payments.order(created_at: :desc).limit(20)
  end

  def edit; end

  def update
    old_plan = @subscription.plan
    if @subscription.update(subscription_params)
      # Apply standard limits when changing plan
      if @subscription.plan != old_plan
        limits   = PlanConfig.limits_for(@subscription.plan)
        features = PlanConfig.features_for(@subscription.plan)
        @subscription.update_columns(
          max_surveys:       limits[:max_surveys],
          max_votes:         limits[:max_votes],
          max_feedbacks:     limits[:max_feedbacks],
          max_supporters:    limits[:max_supporters],
          max_ai_credits:    limits[:max_ai_credits],
          max_dynamic_forms: limits[:max_dynamic_forms],
          credit_balance:    limits[:max_ai_credits] || 0,
          features:          features
        )
      end
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
    params.require(:subscription).permit(
      :plan, :status, :starts_at, :ends_at, :auto_renew,
      :credit_balance, :max_surveys, :max_votes, :max_feedbacks,
      :max_supporters, :max_ai_credits, :price_cents, :billing_cycle
    )
  end
end
