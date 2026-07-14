class Learner::RegistrationsController < Devise::RegistrationsController
  layout "learner"
  skip_before_action :authenticate_user!
  skip_before_action :set_current_workspace

  protected

  def after_sign_up_path_for(resource)
    sign_out resource
    flash[:notice] = t('learner_auth.signup_success')
    new_learner_session_path(email: resource.email)
  end

  def sign_up_params
    params.require(:learner).permit(:name, :email, :password, :password_confirmation)
  end
end
