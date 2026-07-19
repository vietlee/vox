class Api::Learner::V1::CreditsController < Api::Learner::V1::BaseController
  PRICE_PER_CREDIT = 1_000
  PENDING_TTL      = 20.minutes

  def index
    expire_stale_pending!
    payments = current_learner.learner_payments.order(created_at: :desc).limit(5)
    render json: {
      credits:          current_learner.credits,
      max_credits:      current_learner.max_credits,
      price_per_credit: PRICE_PER_CREDIT,
      monthly_free:     Learner::MONTHLY_FREE_CREDITS,
      payments: payments.map { |p|
        { id: p.id, amount_cents: p.amount_cents, credits_amount: p.credits_amount,
          status: p.status, created_at: p.created_at }
      }
    }
  end

  def checkout
    amount = params[:amount].to_i
    unless amount >= 10
      return render json: { error: "Vui lòng mua ít nhất 10 credits." }, status: :unprocessable_entity
    end

    total_cents  = amount * PRICE_PER_CREDIT
    order_code   = Time.current.to_i * 100 + current_learner.id % 100

    payment = current_learner.learner_payments.create!(
      amount_cents:     total_cents,
      currency:         "VND",
      credits_amount:   amount,
      status:           :pending,
      gateway:          :payos,
      payos_order_code: order_code,
      invoice_number:   "LP-#{order_code}"
    )

    result = PayosService.new.create_payment_link(
      order_code:  order_code,
      amount:      total_cents,
      description: "VOX Credits #{amount}",
      return_url:  learner_credits_return_url(payment_id: payment.id),
      cancel_url:  learner_credits_cancel_url(payment_id: payment.id),
      expired_at:  15.minutes.from_now
    )

    if result
      payment.update_column(:payment_link_id, result["paymentLinkId"])
      render json: { checkout_url: result["checkoutUrl"] }
    else
      payment.update_column(:status, LearnerPayment.statuses[:failed])
      render json: { error: "Không thể kết nối PayOS. Vui lòng thử lại." }, status: :unprocessable_entity
    end
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def payment_status
    payment = current_learner.learner_payments.find_by(id: params[:id])
    if payment&.completed?
      render json: { status: "completed", credits: current_learner.reload.credits, bought: payment.credits_amount }
    elsif payment&.failed?
      render json: { status: "failed" }
    else
      render json: { status: "pending" }
    end
  end

  private

  def expire_stale_pending!
    current_learner.learner_payments
                   .where(status: LearnerPayment.statuses[:pending])
                   .where("created_at < ?", PENDING_TTL.ago)
                   .update_all(status: LearnerPayment.statuses[:failed])
  end
end
