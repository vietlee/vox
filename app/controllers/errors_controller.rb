class ErrorsController < ActionController::Base
  include Devise::Controllers::Helpers

  layout "participate"

  before_action :set_locale

  def not_found
    respond_to do |format|
      format.html { render "participate/errors/not_found", status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
      format.any  { head :not_found }
    end
  end

  def server_error
    respond_to do |format|
      format.html { render "participate/errors/server_error", status: :internal_server_error }
      format.json { render json: { error: "Internal server error" }, status: :internal_server_error }
      format.any  { head :internal_server_error }
    end
  end

  def unprocessable
    respond_to do |format|
      format.html { render "participate/errors/not_found", status: :unprocessable_entity }
      format.json { render json: { error: "Unprocessable entity" }, status: :unprocessable_entity }
      format.any  { head :unprocessable_entity }
    end
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
