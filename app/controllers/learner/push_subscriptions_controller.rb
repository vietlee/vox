class Learner::PushSubscriptionsController < Learner::BaseController
  def create
    sub_params = params.require(:subscription)
    endpoint = sub_params[:endpoint]
    return render json: { error: "missing endpoint" }, status: :unprocessable_entity if endpoint.blank?

    keys = sub_params[:keys] || {}
    sub = current_learner.learner_push_subscriptions.find_or_initialize_by(endpoint: endpoint)
    sub.assign_attributes(
      p256dh_key:    keys[:p256dh],
      auth_key:      keys[:auth],
      reminder_hour: params[:reminder_hour] || "20",
      active:        true
    )
    sub.save!
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
