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
end
