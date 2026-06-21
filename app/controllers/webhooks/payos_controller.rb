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
        payment.update_columns(
          status:                 Payment.statuses[:completed],
          gateway_transaction_id: payload.dig("data", "reference").to_s,
          gateway_response:       payload,
          paid_at:                Time.current
        )
        activate_addon!(payment) if payment.addon_config_id?
      end
    when "01", "02"
      payment.update_columns(
        status:           Payment.statuses[:failed],
        gateway_response: payload
      )
    end

    render json: { success: true }
  rescue JSON::ParserError
    render json: { error: "Invalid JSON" }, status: :bad_request
  rescue => e
    Rails.logger.error("[PayOS webhook] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    render json: { error: "Server error" }, status: :internal_server_error
  end

  private

  def activate_addon!(payment)
    addon = payment.addon_config
    sub   = payment.subscription
    return unless addon && sub

    updates = {}
    if addon.ai_credits_bonus.to_i > 0
      updates[:credit_balance] = sub.credit_balance.to_i + addon.ai_credits_bonus.to_i
      updates[:max_ai_credits] = sub.max_ai_credits.to_i + addon.ai_credits_bonus.to_i if sub.max_ai_credits
    end

    sub.update_columns(updates) if updates.any?
  end
end
