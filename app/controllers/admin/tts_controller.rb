class Admin::TtsController < Admin::BaseController
  before_action :check_tts_feature, only: [:voices, :generate]

  def index
    @has_tts = current_workspace&.feature_subscription&.has_feature?(:tts)
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

    speed         = (params[:speed].presence      || 1.0).to_f.clamp(0.7, 1.2)
    stability     = (params[:stability].presence  || 0.5).to_f.clamp(0.0, 1.0)
    similarity    = (params[:similarity].presence || 0.75).to_f.clamp(0.0, 1.0)
    style         = (params[:style].presence      || 0.0).to_f.clamp(0.0, 1.0)
    language_code = params[:language_code].presence
    output_format = params[:output_format].presence&.then { |f|
      %w[mp3_44100_64 mp3_44100_128 mp3_44100_192].include?(f) ? f : "mp3_44100_128"
    } || "mp3_44100_128"

    cache_key = tts_cache_key(text, voice_id, model, speed, stability, similarity, style, output_format, language_code)
    cached    = Rails.cache.read(cache_key)

    if cached
      response.headers["X-Credits-Used"] = "0"
      response.headers["X-Cache"]        = "HIT"
      send_data cached,
        type:        "audio/mpeg",
        disposition: "inline",
        filename:    "tts-#{Time.current.to_i}.mp3"
      return
    end

    skip_credits = params[:source] == "flashcard"
    unless skip_credits
      credits_needed = tts_credits_for(text, model)
      return unless require_credits!(credits_needed)
    end

    text = normalize_for_tts(text) if vietnamese_text?(text) && params[:skip_normalize] != 'true'

    service = ElevenLabsService.new
    tts_opts = {
      text:          text,
      voice_id:      voice_id,
      model:         model,
      speed:         speed,
      stability:     stability,
      similarity:    similarity,
      style:         style,
      output_format: output_format
    }
    tts_opts[:language_code] = language_code if language_code
    audio = service.text_to_speech(**tts_opts)

    Rails.cache.write(cache_key, audio, expires_in: 24.hours)
    current_subscription&.deduct_credits!(credits_needed) unless skip_credits

    response.headers["X-Credits-Used"] = credits_needed.to_s
    response.headers["X-Cache"]        = "MISS"

    send_data audio,
      type:        "audio/mpeg",
      disposition: "inline",
      filename:    "tts-#{Time.current.to_i}.mp3"
  rescue ElevenLabsService::Error => e
    render json: { error: e.message, error_code: e.code, http_status: e.http_status }, status: :service_unavailable
  rescue => e
    render json: { error: e.message, error_code: :unknown }, status: :service_unavailable
  end

  private

  def check_tts_feature
    return if %w[flashcard voice_call].include?(params[:source])
    unless current_workspace&.feature_subscription&.has_feature?(:tts)
      render json: { error: t("tts.upgrade_required"), upgrade_required: true }, status: :payment_required
    end
  end

  # Credit cost by model (chars needed per 1 credit)
  # Flash v2.5 ($0.05/1K): 500 chars/credit
  # Multilingual v2 ($0.10/1K): 250 chars/credit
  # Eleven v3 ($0.10/1K): 250 chars/credit
  TTS_CHARS_PER_CREDIT = {
    "eleven_flash_v2_5"      => 500,
    "eleven_turbo_v2_5"      => 500,  # alias for Flash v2.5
    "eleven_turbo_v2"        => 500,
    "eleven_multilingual_v2" => 250,
    "eleven_multilingual_v3" => 250,
    "eleven_v3"              => 250,
    "eleven_monolingual_v1"  => 250,
  }.freeze

  def vietnamese_text?(text)
    # Check for Vietnamese diacritical characters
    text.match?(/[àáạảãăắặẳẵâấậẩẫèéẹẻẽêếệểễìíịỉĩòóọỏõôốộổỗơớợởỡùúụủũưứựửữỳýỵỷỹđÀÁẠẢÃĂẮẶẲẴÂẤẬẨẪÈÉẸẺẼÊẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỐỘỔỖƠỚỢỞỠÙÚỤỦŨƯỨỰỬỮỲÝỴỶỸĐ]/)
  end

  def normalize_for_tts(text)
    svc = ClaudeService.for_feature("ai_chat")
    result = svc.call(
      system_prompt: "Bạn là công cụ chuẩn hóa văn bản tiếng Việt cho hệ thống Text-to-Speech. Chỉ trả về văn bản đã chuẩn hóa, không giải thích.",
      user_prompt: <<~PROMPT,
        Chuẩn hóa đoạn văn bản sau để đọc to rõ ràng bằng giọng nói tiếng Việt. Áp dụng các quy tắc:
        1. Dấu "/" giữa các từ → đọc là ", " (ví dụ: "bố/cha" → "bố, cha")
        2. Viết tắt thông dụng → viết đầy đủ (VD: "TP.HCM" → "Thành phố Hồ Chí Minh", "GS" → "Giáo sư", "PGS.TS" → "Phó Giáo sư Tiến sĩ")
        3. Số → chữ khi cần thiết (VD: "100%" → "một trăm phần trăm", "2/3" → "hai phần ba")
        4. Ký hiệu đặc biệt → cách đọc (VD: "&" → "và", "+" → "cộng", "=" → "bằng", "@" → "a còng")
        5. Từ tiếng Anh trong câu tiếng Việt → giữ nguyên (TTS đọc được)
        6. Giữ nguyên dấu câu (chấm, phẩy, dấu hỏi...)
        7. KHÔNG thay đổi nội dung, chỉ chuẩn hóa cách viết

        Văn bản gốc:
        #{text}
      PROMPT
      max_tokens: [text.length * 2, 1000].max
    )
    result.strip.presence || text
  rescue => e
    Rails.logger.warn "[TTS normalize] Failed: #{e.message}"
    text
  end

  def tts_cache_key(text, voice_id, model, speed, stability, similarity, style, output_format, language_code = nil)
    digest = Digest::SHA256.hexdigest([text, voice_id, model, speed, stability, similarity, style, output_format, language_code].join("|"))
    "tts/audio/#{digest}"
  end

  def tts_credits_for(text, model = "eleven_turbo_v2_5")
    chars_per_credit = TTS_CHARS_PER_CREDIT[model] || 250
    [(text.length / chars_per_credit.to_f).ceil, 1].max
  end
end
