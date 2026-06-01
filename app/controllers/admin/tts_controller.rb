class Admin::TtsController < Admin::BaseController
  before_action :check_tts_feature, only: [:voices, :generate]

  def index
    @has_tts = current_workspace&.active_subscription&.has_feature?(:tts)
  end

  def voices
    service = ElevenLabsService.new
    render json: service.voices
  rescue => e
    render json: { error: e.message }, status: :service_unavailable
  end

  def generate
    text     = params[:text].to_s.strip
    voice_id = params[:voice_id].presence || ElevenLabsService::DEFAULT_VOICE
    model    = params[:model].presence    || "eleven_turbo_v2_5"

    if text.blank?
      render json: { error: "Vui lòng nhập nội dung văn bản" }, status: :unprocessable_entity
      return
    end

    if text.length > 5000
      render json: { error: "Văn bản quá dài (tối đa 5000 ký tự)" }, status: :unprocessable_entity
      return
    end

    credits_needed = tts_credits_for(text)
    return unless require_credits!(credits_needed)

    stability  = (params[:stability].presence  || 0.5).to_f.clamp(0.0, 1.0)
    similarity = (params[:similarity].presence || 0.75).to_f.clamp(0.0, 1.0)
    style      = (params[:style].presence      || 0.0).to_f.clamp(0.0, 1.0)

    service = ElevenLabsService.new
    audio   = service.text_to_speech(
      text:       text,
      voice_id:   voice_id,
      model:      model,
      stability:  stability,
      similarity: similarity,
      style:      style
    )

    current_workspace.active_subscription&.deduct_credits!(credits_needed)

    send_data audio,
      type:        "audio/mpeg",
      disposition: "inline",
      filename:    "tts-#{Time.current.to_i}.mp3"
  rescue => e
    render json: { error: e.message }, status: :service_unavailable
  end

  private

  def check_tts_feature
    unless current_workspace&.active_subscription&.has_feature?(:tts)
      render json: { error: t("tts.upgrade_required"), upgrade_required: true }, status: :payment_required
    end
  end

  # 1 credit per 500 chars, minimum 1
  def tts_credits_for(text)
    [(text.length / 500.0).ceil, 1].max
  end
end
