class Api::Learner::V1::ProfileController < Api::Learner::V1::BaseController
  def show
    l = current_learner
    render json: {
      id: l.id,
      name: l.name,
      email: l.email,
      credits: l.credits,
      max_credits: l.max_credits,
      xp: l.xp,
      current_streak: l.current_streak,
      longest_streak: l.longest_streak,
      daily_goal: l.daily_goal,
      preferred_locale: l.preferred_locale,
      sign_in_count: l.sign_in_count,
      created_at: l.created_at
    }
  end

  def update
    permitted = params.require(:learner).permit(:name, :daily_goal)
    permitted[:daily_goal] = permitted[:daily_goal].to_i.clamp(1, 20) if permitted[:daily_goal].present?

    if current_learner.update(permitted)
      render json: { ok: true, learner: learner_json(current_learner) }
    else
      render json: { ok: false, errors: current_learner.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  def change_password
    current_pw  = params.dig(:learner, :current_password).to_s
    new_pw      = params.dig(:learner, :password).to_s
    new_pw_conf = params.dig(:learner, :password_confirmation).to_s

    unless current_learner.valid_password?(current_pw)
      return render json: { error: "Mật khẩu hiện tại không đúng." }, status: :unprocessable_entity
    end
    if new_pw.length < 8
      return render json: { error: "Mật khẩu mới phải có ít nhất 8 ký tự." }, status: :unprocessable_entity
    end
    if new_pw != new_pw_conf
      return render json: { error: "Xác nhận mật khẩu không khớp." }, status: :unprocessable_entity
    end

    current_learner.update!(password: new_pw, password_confirmation: new_pw_conf)
    bypass_sign_in(current_learner, scope: :learner)
    render json: { ok: true }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
