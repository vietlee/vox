class Participate::BaseController < ActionController::Base
  layout "participate"
  before_action :set_locale_from_workspace

  private

  def set_locale_from_workspace
    if params[:locale].present? && %w[vi en].include?(params[:locale])
      cookies[:participate_locale] = { value: params[:locale], expires: 1.year.from_now }
    end
    user_locale = cookies[:participate_locale]
    I18n.locale = (user_locale.presence || @workspace&.language || "vi").to_sym
  end

  def respondent_token
    cookies.permanent[:respondent_token] ||= SecureRandom.urlsafe_base64(16)
  end

  def current_user
    request.env["warden"]&.user(:user)
  end

  def require_login!(return_to: request.url)
    unless current_user
      session["user_return_to"] = return_to
      redirect_to new_user_session_path, alert: t("errors.login_required")
    end
  end
end
