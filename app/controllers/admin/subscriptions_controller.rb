class Admin::SubscriptionsController < Admin::BaseController
  before_action :require_admin!

  def show
    @subscription  = current_workspace.active_subscription || ensure_subscription!
    @addon_credits = AddonConfig.active.ai_credits
    @payments      = current_workspace.payments.includes(:addon_config, :subscription).order(created_at: :desc).limit(10)
  end

  def billing
    @subscription  = current_workspace.active_subscription || ensure_subscription!
    @addon_credits = AddonConfig.active.ai_credits
  end

  # POST /subscription/checkout_addon — buy AI credits
  def checkout_addon
    addon = AddonConfig.active.ai_credits.find_by(id: params[:addon_config_id])
    unless addon
      redirect_to subscription_path, alert: t("subscription_errors.addon_not_found") and return
    end

    sub = current_workspace.active_subscription || ensure_subscription!

    order_code = Time.current.to_i * 10 + current_workspace.id % 10

    payment = sub.payments.create!(
      workspace:        current_workspace,
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
    @payment = current_workspace.payments.find_by(id: params[:payment_id])
    if @payment&.completed?
      redirect_to subscription_path, notice: t("subscription.addon_purchase_success", bonus: @payment.addon_config&.bonus_summary)
    else
      render :payment_pending, layout: "participate"
    end
  end

  def payment_status
    payment = current_workspace.payments.find_by(id: params[:payment_id])
    if payment&.completed?
      render json: { status: "completed" }
    elsif payment&.failed?
      render json: { status: "failed" }
    else
      render json: { status: "pending" }
    end
  end

  def payment_cancel
    payment = current_workspace.payments.find_by(id: params[:payment_id])
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

  def ensure_subscription!
    current_workspace.subscriptions.create!(
      plan:           :free,
      status:         :active,
      starts_at:      Time.current,
      credit_balance: Subscription.monthly_free_credits,
      max_ai_credits: Subscription.monthly_free_credits
    )
  end
end
