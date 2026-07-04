class Learner::SessionsController < Devise::SessionsController
  layout "learner"
  skip_before_action :authenticate_user!
  skip_before_action :set_current_workspace

  protected

  def after_sign_in_path_for(resource)
    learner_root_path
  end

  def after_sign_out_path_for(resource_or_scope)
    new_learner_session_path
  end
end
