class Admin::TtsController < Admin::BaseController
  def index
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
    model    = params[:model].presence    || "eleven_multilingual_v2"

    if text.blank?
      render json: { error: "Text cannot be blank" }, status: :unprocessable_entity
      return
    end

    if text.length > 5000
      render json: { error: "Text is too long (max 5000 characters)" }, status: :unprocessable_entity
      return
    end

    service  = ElevenLabsService.new
    audio    = service.text_to_speech(text: text, voice_id: voice_id, model: model)

    send_data audio,
      type:        "audio/mpeg",
      disposition: "inline",
      filename:    "tts-#{Time.current.to_i}.mp3"
  rescue => e
    render json: { error: e.message }, status: :service_unavailable
  end
end
