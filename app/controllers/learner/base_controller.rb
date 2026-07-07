class Learner::BaseController < ApplicationController
  layout "learner"

  before_action :authenticate_learner!
  before_action :touch_last_seen!
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

  def touch_last_seen!
    return unless current_learner
    return if current_learner.last_seen_at && current_learner.last_seen_at > 2.minutes.ago
    current_learner.update_column(:last_seen_at, Time.current)
  end

  def authenticate_learner!
    unless current_learner
      store_location_for(:learner, request.fullpath)
      redirect_to new_learner_session_path, alert: "Vui lòng đăng nhập để tiếp tục."
    end
  end

  def pagy(scope, items: 10, page: nil)
    page  = (page || 1).to_i
    total = scope.count
    pages = [(total.to_f / items).ceil, 1].max
    page  = [[page, 1].max, pages].min
    records  = scope.offset((page - 1) * items).limit(items)
    prev_p   = page > 1 ? page - 1 : nil
    next_p   = page < pages ? page + 1 : nil
    pagy_obj = Struct.new(:page, :items, :count, :pages, :prev, :next)
                     .new(page, items, total, pages, prev_p, next_p)
    [pagy_obj, records]
  end
end
