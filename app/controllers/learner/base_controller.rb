class Learner::BaseController < ApplicationController
  layout "learner"

  before_action :authenticate_learner!
  skip_before_action :authenticate_user!
  skip_before_action :set_current_workspace

  helper_method :current_learner

  private

  def current_learner
    @current_learner ||= warden.authenticate(scope: :learner)
  end

  def authenticate_learner!
    unless current_learner
      store_location_for(:learner, request.fullpath)
      redirect_to new_learner_session_path, alert: "Vui lòng đăng nhập để tiếp tục."
    end
  end
end
