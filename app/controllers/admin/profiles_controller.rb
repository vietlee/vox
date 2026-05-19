class Admin::ProfilesController < Admin::BaseController
  def show; end

  def update
    if params[:current_password].present? || params[:new_password].present?
      update_password
    else
      update_name
    end
  end

  private

  def update_name
    if current_user.update(name: params[:name])
      redirect_to profile_path, notice: t("profile.updated")
    else
      flash.now[:alert] = current_user.errors.full_messages.join(", ")
      render :show, status: :unprocessable_entity
    end
  end

  def update_password
    unless current_user.valid_password?(params[:current_password])
      flash.now[:alert] = t("profile.password_wrong")
      return render :show, status: :unprocessable_entity
    end

    if params[:new_password] != params[:confirm_password]
      flash.now[:alert] = t("profile.password_mismatch")
      return render :show, status: :unprocessable_entity
    end

    current_user.update!(
      name: params[:name],
      password: params[:new_password],
      password_confirmation: params[:confirm_password],
      must_change_password: false
    )
    bypass_sign_in(current_user)
    redirect_to profile_path, notice: t("profile.updated")
  end
end
