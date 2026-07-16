class Learner::PushSubscriptionsController < Learner::BaseController
  def create
    sub_params = params.require(:subscription)
    endpoint = sub_params[:endpoint]
    return render json: { error: "missing endpoint" }, status: :unprocessable_entity if endpoint.blank?

    keys = sub_params[:keys] || {}
    hour = (params[:reminder_hour] || "20").to_s
    sub = current_learner.learner_push_subscriptions.find_or_initialize_by(endpoint: endpoint)
    is_new = sub.new_record?
    sub.assign_attributes(
      p256dh_key:    keys[:p256dh],
      auth_key:      keys[:auth],
      reminder_hour: hour,
      active:        true
    )
    sub.save!

    # Sync reminder hour across all other active subscriptions (multi-device)
    current_learner.learner_push_subscriptions.where(active: true)
                   .where.not(id: sub.id)
                   .update_all(reminder_hour: hour)

    # Fire a test push immediately on first subscribe so the user gets instant confirmation
    # that notifications are working — and to detect stale subscriptions early.
    if is_new
      PushNotificationService.send_to_subscription(
        sub,
        title: "✅ Thông báo VOX đã bật",
        body:  "Bạn sẽ nhận nhắc học lúc #{hour}:00 mỗi ngày.",
        url:   "/learner/profile"
      )
    end

    render json: { ok: true }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    current_learner.learner_push_subscriptions
                   .find_by(endpoint: params[:endpoint])
                   &.update_columns(active: false)
    render json: { ok: true }
  end
end
