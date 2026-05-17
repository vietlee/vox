class Participate::BaseController < ActionController::Base
  layout "participate"
  before_action :set_locale_from_workspace

  private

  def set_locale_from_workspace
    I18n.locale = @workspace&.language&.to_sym || :vi
  end

  def respondent_token
    cookies.permanent[:respondent_token] ||= SecureRandom.urlsafe_base64(16)
  end

  def current_user
    request.env["warden"]&.user(:user)
  end

  def require_login!(return_to: request.url)
    unless current_user
      session[:user_return_to] = return_to
      redirect_to new_user_session_path, alert: "Bạn cần đăng nhập để tiếp tục."
    end
  end
end
