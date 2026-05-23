class PagesController < ActionController::Base
  include Devise::Controllers::Helpers

  before_action :set_locale

  layout "public"

  def home
    # Redirect logged-in users straight to their dashboard
    if user_signed_in?
      redirect_to dashboard_path and return
    end
  end

  private

  def set_locale
    if params[:locale].present? && I18n.available_locales.map(&:to_s).include?(params[:locale])
      session[:locale] = params[:locale]
    end
    I18n.locale = session[:locale]&.to_sym || :vi
  end
end
