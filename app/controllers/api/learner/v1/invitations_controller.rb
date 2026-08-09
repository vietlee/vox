# Native (app) counterpart of Learner::InvitationsController.
# Lets the Flutter app accept a teacher's invite via a deep-linked token:
# fetch the invitee's info, then set a password and sign in — all in-app,
# so a learner who opened the invite email in the installed app never has to
# bounce out to the PWA.
class Api::Learner::V1::InvitationsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :set_current_workspace
  skip_forgery_protection

  # GET /api/learner/v1/invite/:token
  # Prefill the set-password screen; also tells the app whether the invite is
  # still actionable or the account was already set up.
  def show
    learner = Learner.find_by(invite_token: params[:token])
    if learner.nil?
      return render json: { error: "Link không hợp lệ hoặc đã hết hạn." }, status: :not_found
    end

    render json: {
      name:  learner.name,
      email: learner.email,
      already_set: learner.password_set?
    }
  end

  # POST /api/learner/v1/invite/:token/accept  { password:, password_confirmation: }
  def accept
    learner = Learner.find_by(invite_token: params[:token])
    if learner.nil?
      return render json: { error: "Link không hợp lệ hoặc đã hết hạn." }, status: :not_found
    end

    if learner.password_set?
      return render json: { error: "Tài khoản đã được thiết lập. Vui lòng đăng nhập." },
                    status: :unprocessable_entity
    end

    password = params[:password].to_s
    confirmation = params[:password_confirmation].to_s

    if password.length < 8
      return render json: { error: "Mật khẩu phải có ít nhất 8 ký tự." },
                    status: :unprocessable_entity
    end

    if password != confirmation
      return render json: { error: "Xác nhận mật khẩu không khớp." },
                    status: :unprocessable_entity
    end

    if learner.update(password: password, password_confirmation: confirmation,
                      password_set: true, invite_token: nil)
      learner.remember_me = true
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
      render json: { error: learner.errors.full_messages.first || "Không thể thiết lập tài khoản." },
             status: :unprocessable_entity
    end
  end
end
