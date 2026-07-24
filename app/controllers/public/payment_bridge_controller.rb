class Public::PaymentBridgeController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :authenticate_learner!, raise: false
  layout false

  # GET /payment/app_return?payment_id=X&status=PAID&code=00
  # Called by PayOS after successful payment from Flutter in-app browser.
  # No session auth required — credits are added by webhook; this page just
  # triggers the deep-link redirect back to the app.
  def app_return
    @payment_id = params[:payment_id].to_i
    payment = LearnerPayment.find_by(id: @payment_id)

    # Best-effort: verify + credit if webhook hasn't fired yet
    if payment && payment.pending? && (params[:status] == "PAID" || params[:code] == "00")
      info = PayosService.new.get_payment_info(payment.payos_order_code)
      if info && info["status"] == "PAID"
        ActiveRecord::Base.transaction do
          payment.update_column(:status, LearnerPayment.statuses[:completed])
          payment.learner.add_credits!(payment.credits_amount)
        end unless payment.reload.completed?
      end
    end

    @deep_link = "voxlearner://credits/return?payment_id=#{@payment_id}&status=PAID"
  end

  # GET /payment/app_cancel?payment_id=X
  def app_cancel
    @payment_id = params[:payment_id].to_i
    payment = LearnerPayment.find_by(id: @payment_id)
    payment&.update_column(:status, LearnerPayment.statuses[:failed]) if payment&.pending?
    @deep_link = "voxlearner://credits/cancel?payment_id=#{@payment_id}"
  end
end
