class Learner::PushSubscriptionsController < Learner::BaseController
  def create
    sub_params = params.require(:subscription)
    endpoint = sub_params[:endpoint]
    return render json: { error: "missing endpoint" }, status: :unprocessable_entity if endpoint.blank?

    keys = sub_params[:keys] || {}
    hour = (params[:reminder_hour] || "20").to_s
    sub = current_learner.learner_push_subscriptions.find_or_initialize_by(endpoint: endpoint)
    sub.assign_attributes(
      p256dh_key:    keys[:p256dh],
      auth_key:      keys[:auth],
      reminder_hour: hour,
      active:        true
    )
    sub.save!
    # Keep the chosen hour consistent across ALL of this learner's devices/subscriptions
    # (reinstalls create new endpoints; otherwise old subs keep a stale hour and fire
    # reminders at the wrong times).
    current_learner.learner_push_subscriptions.where(active: true)
                   .where.not(id: sub.id)
                   .update_all(reminder_hour: hour)
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
