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
        if payment.addon_config_id?
          activate_addon!(payment)
        else
          activate_subscription!(payment)
        end
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
    updates = {}

    # Only add to capped limits (nil = unlimited, no need to bump)
    updates[:max_surveys]   = sub.max_surveys.to_i   + addon.surveys_bonus.to_i   if sub.max_surveys   && addon.surveys_bonus.to_i > 0
    updates[:max_votes]     = sub.max_votes.to_i     + addon.votes_bonus.to_i     if sub.max_votes     && addon.votes_bonus.to_i > 0
    updates[:max_feedbacks] = sub.max_feedbacks.to_i + addon.feedbacks_bonus.to_i if sub.max_feedbacks && addon.feedbacks_bonus.to_i > 0

    if addon.ai_credits_bonus.to_i > 0
      updates[:credit_balance] = sub.credit_balance.to_i + addon.ai_credits_bonus.to_i
    end

    sub.update_columns(updates) if updates.any?
  end

  def activate_subscription!(payment)
    sub  = payment.subscription
    plan = sub.plan  # already set tentatively in checkout action

    limits   = PlanConfig.limits_for(plan)
    features = PlanConfig.features_for(plan)

    # If current ends_at is nil (free plan) or already past, start fresh from now.
    # If still in future (renewing before expiry), extend from that date.
    base = (sub.ends_at.present? && sub.ends_at > Time.current) ? sub.ends_at : Time.current
    new_ends_at = base + 1.month

    sub.update_columns(
      status:         Subscription.statuses[:active],
      ends_at:        new_ends_at,
      max_surveys:    limits[:max_surveys],
      max_votes:      limits[:max_votes],
      max_feedbacks:  limits[:max_feedbacks],
      max_supporters: limits[:max_supporters],
      max_ai_credits: limits[:max_ai_credits],
      credit_balance: limits[:max_ai_credits] || 0,
      features:       features
    )
  end
end
