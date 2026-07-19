class Api::Learner::V1::SessionsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :set_current_workspace
  skip_forgery_protection

  def create
    learner = Learner.find_by(email: params.dig(:learner, :email).to_s.strip.downcase)
    if learner&.valid_password?(params.dig(:learner, :password).to_s)
      sign_in(:learner, learner)
      learner.update_column(:last_seen_at, Time.current)
      render json: {
        learner: {
          id: learner.id, name: learner.name, email: learner.email,
          credits: learner.credits, xp: learner.xp,
          current_streak: learner.current_streak, daily_goal: learner.daily_goal,
          preferred_locale: learner.preferred_locale
        }
      }
    else
      render json: { error: "Email hoặc mật khẩu không đúng." }, status: :unauthorized
    end
  end

  def destroy
    sign_out(:learner)
    render json: { ok: true }
  end

  def me
    learner = warden.authenticate(scope: :learner)
    if learner
      render json: { learner: {
        id: learner.id, name: learner.name, email: learner.email,
        credits: learner.credits, xp: learner.xp,
        current_streak: learner.current_streak, daily_goal: learner.daily_goal,
        preferred_locale: learner.preferred_locale
      }}
    else
      render json: { error: "Not authenticated" }, status: :unauthorized
    end
  end
end
