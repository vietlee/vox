class Admin::SubscriptionsController < Admin::BaseController
  before_action :require_admin!

  def show
    @subscription  = user_subscription
    @addon_credits = AddonConfig.active.ai_credits
    # Payment history: all payments across workspaces the user owns
    primary_ws = current_user.owned_workspaces.order(:id).first
    @payments = primary_ws ? primary_ws.payments.includes(:addon_config, :subscription).order(created_at: :desc).limit(10) : Payment.none
  end

  def billing
    @subscription  = user_subscription
    @addon_credits = AddonConfig.active.ai_credits
  end

  # POST /subscription/checkout_addon — buy AI credits → always tops up user's subscription
  def checkout_addon
    addon = AddonConfig.active.ai_credits.find_by(id: params[:addon_config_id])
    unless addon
      redirect_to subscription_path, alert: t("subscription_errors.addon_not_found") and return
    end

    sub = user_subscription

    order_code = Time.current.to_i * 10 + current_user.id % 10

    payment = sub.payments.create!(
      workspace:        sub.workspace,
      addon_config:     addon,
      amount_cents:     addon.price_cents,
      currency:         "VND",
      status:           :pending,
      gateway:          :payos,
      payos_order_code: order_code,
      invoice_number:   "ADDON-#{order_code}"
    )

    service = PayosService.new
    result  = service.create_payment_link(
      order_code:  order_code,
      amount:      addon.price_cents,
      description: "VOX AI Credits #{addon.name.truncate(15)}",
      return_url:  payment_return_subscription_url(payment_id: payment.id),
      cancel_url:  payment_cancel_subscription_url(payment_id: payment.id),
      expired_at:  15.minutes.from_now
    )

    if result
      payment.update_column(:payment_link_id, result["paymentLinkId"])
      redirect_to result["checkoutUrl"], allow_other_host: true
    else
      payment.update_columns(status: Payment.statuses[:failed])
      redirect_to subscription_path, alert: t("subscription_errors.payos_error")
    end
  end

  def payment_return
    @payment = Payment.joins(subscription: { workspace: :owner })
                      .where(workspaces: { owner_id: current_user.id })
                      .find_by(id: params[:payment_id])
    if @payment&.completed?
      redirect_to subscription_path, notice: t("subscription.addon_purchase_success", bonus: @payment.addon_config&.bonus_summary)
    else
      render :payment_pending, layout: "participate"
    end
  end

  def payment_status
    payment = Payment.joins(subscription: { workspace: :owner })
                     .where(workspaces: { owner_id: current_user.id })
                     .find_by(id: params[:payment_id])
    if payment&.completed?
      render json: { status: "completed" }
    elsif payment&.failed?
      render json: { status: "failed" }
    else
      render json: { status: "pending" }
    end
  end

  def payment_cancel
    payment = Payment.joins(subscription: { workspace: :owner })
                     .where(workspaces: { owner_id: current_user.id })
                     .find_by(id: params[:payment_id])
    payment&.update_column(:status, Payment.statuses[:failed])
    redirect_to subscription_path, alert: t("subscription_errors.payment_cancelled")
  end

  # Legacy routes — redirect to show
  def upgrade  = redirect_to(subscription_path)
  def cancel   = redirect_to(subscription_path)
  def invoices = redirect_to(subscription_path)
  def update   = redirect_to(subscription_path)
  def checkout = redirect_to(subscription_path)

  private

  # Always returns the current user's subscription (user-level budget).
  # Creates one on their primary workspace if none exists.
  def user_subscription
    current_user.primary_subscription || create_user_subscription!
  end

  def create_user_subscription!
    ws = current_user.owned_workspaces.order(:id).first || current_workspace
    ws.subscriptions.create!(
      user_id:        current_user.id,
      plan:           :free,
      status:         :active,
      starts_at:      Time.current,
      credit_balance: Subscription.monthly_free_credits,
      max_ai_credits: Subscription.monthly_free_credits
    )
  end
end
