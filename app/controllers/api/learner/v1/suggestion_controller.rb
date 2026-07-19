class Api::Learner::V1::SuggestionController < Api::Learner::V1::BaseController
  def fetch
    sug = current_learner.learner_suggestions.active.order(created_at: :desc).first
    sug ||= LearnerSuggestionService.new(current_learner).fetch
    if sug
      render json: { id: sug.id, kind: sug.kind, icon: sug.icon, title: sug.title,
                     body: sug.body, action_label: sug.action_label,
                     action_url: sug.action_url, prefill_topic: sug.prefill_topic }
    else
      render json: { none: true }
    end
  end

  def dismiss
    sug = current_learner.learner_suggestions.find_by(id: params[:id])
    sug&.update_column(:dismissed_at, Time.current)
    render json: { ok: true }
  end
end
