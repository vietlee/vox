class Admin::SubscriptionsController < Admin::BaseController
  before_action :require_admin!

  def show
    @subscription = current_workspace.active_subscription || current_workspace.subscriptions.order(created_at: :desc).first
    @payments     = current_workspace.payments.order(created_at: :desc).limit(10)
  end

  def billing
    @subscription = current_workspace.active_subscription
  end

  def upgrade
    redirect_to billing_subscription_path
  end

  def cancel
    current_workspace.active_subscription&.update!(auto_renew: false)
    redirect_to subscription_path, notice: t("subscription.cancelled")
  end

  def invoices
    @payments = current_workspace.payments.completed.order(created_at: :desc)
  end

  # POST /subscription/checkout — creates PayOS payment link and redirects
  def checkout
    plan  = params[:plan].to_s
    price = Subscription::PLAN_PRICES[plan].to_i

    unless Subscription::PLAN_PRICES.key?(plan) && price > 0
      redirect_to billing_subscription_path, alert: "Gói không hợp lệ." and return
    end

    sub = current_workspace.active_subscription || current_workspace.subscriptions.create!(
      plan:           :free,
      status:         :active,
      starts_at:      Time.current,
      ends_at:        Time.current + 1.month,
      credit_balance: 0,
      **Subscription::PLAN_LIMITS["free"].transform_values { |v| v || 0 }
    )

    order_code = Time.current.to_i + current_workspace.id

    payment = sub.payments.create!(
      workspace:        current_workspace,
      amount_cents:     price,
      currency:         "VND",
      status:           :pending,
      gateway:          :payos,
      payos_order_code: order_code,
      invoice_number:   "INV-#{order_code}"
    )

    # Tentatively set the plan so webhook knows what to activate
    sub.update_column(:plan, Subscription.plans[plan])

    service = PayosService.new
    result  = service.create_payment_link(
      order_code:  order_code,
      amount:      price,
      description: "VOX #{plan.upcase} #{current_workspace.name.truncate(10)}",
      return_url:  payment_return_subscription_url(payment_id: payment.id),
      cancel_url:  payment_cancel_subscription_url(payment_id: payment.id),
      expired_at:  15.minutes.from_now
    )

    if result
      payment.update_column(:payment_link_id, result["paymentLinkId"])
      redirect_to result["checkoutUrl"], allow_other_host: true
    else
      payment.update!(status: :failed)
      sub.update_column(:plan, Subscription.plans["free"])
      redirect_to billing_subscription_path, alert: "Không thể kết nối PayOS. Vui lòng thử lại."
    end
  end

  # GET /subscription/payment_return — user returns from PayOS checkout page
  def payment_return
    payment = current_workspace.payments.find_by(id: params[:payment_id])

    if payment&.completed?
      redirect_to subscription_path, notice: "Thanh toán thành công! Gói của bạn đã được kích hoạt."
    else
      # Webhook may not have arrived yet — poll for 10s then redirect
      redirect_to subscription_path, notice: "Đang xác nhận thanh toán, vui lòng đợi vài giây..."
    end
  end

  # GET /subscription/payment_cancel
  def payment_cancel
    payment = current_workspace.payments.find_by(id: params[:payment_id])
    payment&.update!(status: :failed)
    redirect_to billing_subscription_path, alert: "Bạn đã huỷ thanh toán."
  end

  def update
    @subscription = current_workspace.active_subscription
    if @subscription.update(subscription_update_params)
      redirect_to subscription_path, notice: t("subscription.updated")
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def subscription_update_params
    if current_user.super_admin?
      params.require(:subscription).permit(:plan, :max_surveys, :max_votes, :max_feedbacks, :max_supporters, :max_ai_credits, :price_cents, :ends_at)
    else
      params.require(:subscription).permit(:auto_renew)
    end
  end
end
