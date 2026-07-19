class Api::Learner::V1::PasswordsController < Api::Learner::V1::BaseController
  skip_before_action :authenticate_learner!
  skip_before_action :touch_last_seen!

  def reset
    learner = Learner.find_by(email: params[:email].to_s.strip.downcase)
    learner&.send_reset_password_instructions
    render json: { ok: true }
  end
end
