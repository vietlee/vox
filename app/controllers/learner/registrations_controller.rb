class Learner::RegistrationsController < Devise::RegistrationsController
  layout "learner"
  skip_before_action :authenticate_user!
  skip_before_action :set_current_workspace

  protected

  def after_sign_up_path_for(resource)
    learner_root_path
  end

  def sign_up_params
    params.require(:learner).permit(:name, :email, :password, :password_confirmation)
  end
end
