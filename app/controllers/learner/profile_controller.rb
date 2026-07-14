class Learner::ProfileController < Learner::BaseController
  def show
    @reminder_hour = current_learner.learner_push_subscriptions
                                    .where(active: true)
                                    .order(updated_at: :desc)
                                    .limit(1).pick(:reminder_hour) || "20"
  end

  def update
    if current_learner.update(profile_params)
      redirect_to learner_profile_path, notice: t('learner_profile.saved')
    else
      render :show, status: :unprocessable_entity
    end
  end

  def change_password
    current_pw  = params[:current_password].to_s
    new_pw      = params[:new_password].to_s
    new_pw_conf = params[:new_password_confirmation].to_s

    unless current_learner.valid_password?(current_pw)
      return redirect_to learner_profile_path(anchor: "pw"), alert: t('learner_profile.pw_wrong_current')
    end
    if new_pw.length < 8
      return redirect_to learner_profile_path(anchor: "pw"), alert: t('learner_profile.pw_too_short')
    end
    if new_pw != new_pw_conf
      return redirect_to learner_profile_path(anchor: "pw"), alert: t('learner_profile.pw_mismatch')
    end

    current_learner.update!(password: new_pw, password_confirmation: new_pw_conf)
    bypass_sign_in(current_learner, scope: :learner)
    redirect_to learner_profile_path, notice: t('learner_profile.pw_changed')
  end

  private

  def profile_params
    params.require(:learner).permit(:name, :daily_goal).tap do |p|
      p[:daily_goal] = p[:daily_goal].to_i.clamp(1, 20) if p[:daily_goal].present?
    end
  end
end
