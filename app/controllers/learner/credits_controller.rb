class Learner::CreditsController < Learner::BaseController
  PRICE_PER_CREDIT = 1_000

  # PayOS payment links expire after 15 min; anything still pending past that
  # window was abandoned (browser back, closed tab, expired link) — mark failed.
  PENDING_TTL = 20.minutes

  def index
    expire_stale_pending!
    @price_per_credit = PRICE_PER_CREDIT
    @monthly_free     = Learner::MONTHLY_FREE_CREDITS
    @payments         = current_learner.learner_payments.order(created_at: :desc).limit(5)
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

  def payment_return
    @payment = current_learner.learner_payments.find_by(id: params[:payment_id])
    return redirect_to learner_credits_path, alert: "Không tìm thấy giao dịch." unless @payment

    if @payment.completed?
      redirect_to learner_credits_path, notice: "Mua thành công #{@payment.credits_amount} credits!"
    elsif params[:status] == "PAID" || params[:code] == "00"
      # PayOS confirmed success in return URL — verify via API and complete if not yet done
      info = PayosService.new.get_payment_info(@payment.payos_order_code)
      if info && info["status"] == "PAID"
        ActiveRecord::Base.transaction do
          @payment.update_column(:status, LearnerPayment.statuses[:completed])
          @payment.learner.add_credits!(@payment.credits_amount)
        end unless @payment.reload.completed?
        redirect_to learner_credits_path, notice: "Mua thành công #{@payment.credits_amount} credits!"
      else
        render :payment_pending
      end
    else
      render :payment_pending
    end
  end

  def payment_cancel
    payment = current_learner.learner_payments.find_by(id: params[:payment_id])
    payment&.update_column(:status, LearnerPayment.statuses[:failed])
    redirect_to learner_credits_path, alert: "Thanh toán đã bị huỷ."
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
