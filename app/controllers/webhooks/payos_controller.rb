class Webhooks::PayosController < ActionController::Base
  skip_forgery_protection

  def receive
    payload = JSON.parse(request.body.read)

    service = PayosService.new
    unless service.verify_webhook(payload)
      render json: { error: "Invalid signature" }, status: :unauthorized and return
    end

    order_code = payload.dig("data", "orderCode").to_i
    payment    = Payment.find_by(payos_order_code: order_code)

    if payment.nil?
      render json: { success: true } and return
    end

    case payload["code"]
    when "00"
      ActiveRecord::Base.transaction do
        payment.update!(
          status:                 :completed,
          gateway_transaction_id: payload.dig("data", "reference").to_s,
          gateway_response:       payload,
          paid_at:                Time.current
        )
        activate_subscription!(payment)
      end
    when "01", "02"
      payment.update!(status: :failed, gateway_response: payload)
    end

    render json: { success: true }
  rescue JSON::ParserError
    render json: { error: "Invalid JSON" }, status: :bad_request
  rescue => e
    Rails.logger.error("[PayOS webhook] #{e.class}: #{e.message}")
    render json: { error: "Server error" }, status: :internal_server_error
  end

  private

  def activate_subscription!(payment)
    sub = payment.subscription
    current_end = [ sub.ends_at || Time.current, Time.current ].max
    sub.update!(
      status:   :active,
      ends_at:  current_end + 1.month,
      plan:     sub.plan  # keep current plan (was set before checkout)
    )
  end
end
