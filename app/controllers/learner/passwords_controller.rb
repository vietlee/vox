class Learner::PasswordsController < Devise::PasswordsController
  layout "learner"
  skip_before_action :authenticate_user!
  skip_before_action :set_current_workspace

  protected

  def after_resetting_password_path_for(resource)
    learner_root_path
  end
end
