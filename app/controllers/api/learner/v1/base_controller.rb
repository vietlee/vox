class Api::Learner::V1::BaseController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :set_current_workspace
  skip_forgery_protection

  before_action :authenticate_learner!
  before_action :touch_last_seen!

  private

  SESSION_TTL = 2.hours

  def current_learner
    @current_learner ||= warden.authenticate(scope: :learner)
  end

  def authenticate_learner!
    render json: { error: "Vui lòng đăng nhập." }, status: :unauthorized unless current_learner
  end

  def touch_last_seen!
    return unless current_learner
    return if current_learner.last_seen_at && current_learner.last_seen_at > 2.minutes.ago
    current_learner.update_column(:last_seen_at, Time.current)
  end

  def learner_json(l)
    { id: l.id, name: l.name, email: l.email, credits: l.credits,
      xp: l.xp, current_streak: l.current_streak, daily_goal: l.daily_goal,
      preferred_locale: l.preferred_locale }
  end

  def pagy(scope, items: 10, page: nil)
    page  = (page || 1).to_i
    total = scope.count
    pages = [(total.to_f / items).ceil, 1].max
    page  = [[page, 1].max, pages].min
    records  = scope.offset((page - 1) * items).limit(items)
    { records: records, page: page, pages: pages, total: total }
  end

  # TTS/STT session helpers (needed by ai_tutor and tools subclasses)
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
end
