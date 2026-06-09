class Participate::BaseController < ActionController::Base
  layout "participate"
  before_action :set_locale_from_workspace

  rescue_from ActiveRecord::RecordNotFound,    with: :render_not_found
  rescue_from ActionController::RoutingError,  with: :render_not_found

  private

  def render_not_found(exception = nil)
    Rails.logger.warn "[Participate] 404 — #{exception&.message} (#{request.path})"
    respond_to do |format|
      format.json { render json: { error: "Not found" }, status: :not_found }
      format.html { render "participate/errors/not_found", status: :not_found, layout: "participate" }
      format.any  { render "participate/errors/not_found", status: :not_found, layout: "participate" }
    end
  end

  def render_server_error(exception = nil)
    Rails.logger.error "[Participate] 500 — #{exception&.message}\n#{exception&.backtrace&.first(5)&.join("\n")}"
    render "participate/errors/server_error", status: :internal_server_error, layout: "participate"
  end

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
      session["user_return_to"]      = return_to  # Devise stored location
      session[:omniauth_return_to]   = return_to  # SSO participant context detection
      redirect_to new_user_session_path, alert: t("errors.login_required")
    end
  end
end
