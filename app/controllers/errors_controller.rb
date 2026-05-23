class ErrorsController < ActionController::Base
  include Devise::Controllers::Helpers

  layout "participate"

  before_action :set_locale

  def not_found
    render "participate/errors/not_found", status: :not_found
  end

  def server_error
    render "participate/errors/server_error", status: :internal_server_error
  end

  def unprocessable
    render "participate/errors/not_found", status: :unprocessable_entity
  end

  private

  def set_locale
    if params[:locale].present? && %w[vi en].include?(params[:locale])
      cookies[:participate_locale] = { value: params[:locale], expires: 1.year.from_now }
      session[:locale] = params[:locale]
    end
    locale = cookies[:participate_locale].presence || session[:locale].presence || "vi"
    I18n.locale = locale.to_sym
  rescue
    I18n.locale = :vi
  end
end
