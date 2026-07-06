class Learner::BaseController < ApplicationController
  include Paginatable

  layout "learner"

  before_action :authenticate_learner!
  skip_before_action :authenticate_user!
  skip_before_action :set_current_workspace

  helper_method :current_learner

  private

  SESSION_TTL = 2.hours

  def start_free_tts_session!(key)
    session[key] = Time.current.to_i
  end

  def end_free_tts_session!(key)
    session.delete(key)
  end

  def free_tts_session_active?(key)
    ts = session[key]
    ts.present? && (Time.current.to_i - ts.to_i) < SESSION_TTL
  end

  def in_speaking_session?
    free_tts_session_active?(:sp_active)
  end

  def in_voice_session?
    free_tts_session_active?(:vc_active)
  end

  def default_url_options
    { locale: I18n.locale == I18n.default_locale ? nil : I18n.locale }
  end

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
