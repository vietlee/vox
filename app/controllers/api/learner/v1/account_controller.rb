class Api::Learner::V1::AccountController < Api::Learner::V1::BaseController
  # Permanently deletes the learner and all associated data (App Store
  # guideline 5.1.1(v) requires in-app account deletion). Associations on
  # Learner are dependent: :destroy, so this cascades; referred learners are
  # nullified, not deleted.
  def destroy
    learner = current_learner
    learner.destroy!
    warden.logout(:learner)
    reset_session
    render json: { ok: true }
  rescue => e
    Rails.logger.error "[AccountController#destroy] learner #{current_learner&.id}: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
