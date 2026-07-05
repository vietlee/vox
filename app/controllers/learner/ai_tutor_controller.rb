class Learner::AiTutorController < Learner::BaseController
  CREDIT_COST     = 1
  TTS_CREDIT_COST = 1
  STT_CREDIT_COST = 1

  def index
    @context = params[:context]
    @has_tts = ENV["ELEVENLABS_API_KEY"].present?
    @has_stt = ENV["ELEVENLABS_API_KEY"].present?
  end

  def chat
    return render json: { error: "Không đủ credit. Vui lòng mua thêm." }, status: :payment_required unless current_learner.credits >= CREDIT_COST

    message = params[:message].to_s.strip
    history = Array(params[:history]).last(20)
    context = params[:context].to_s.strip
    return render json: { error: "Tin nhắn trống" }, status: :unprocessable_entity if message.blank?

    system_prompt = build_system_prompt(context)
    messages = history.map { |m| { role: m["role"], content: m["content"].to_s.truncate(2000) } }
    messages << { role: "user", content: message }

    svc      = ClaudeService.for_feature("ai_tutor", timeout: 30)
    response = svc.call(system_prompt: system_prompt, messages: messages, max_tokens: 1000)

    current_learner.deduct_credits!(CREDIT_COST)
    LearnerGamification.record!(current_learner, :tutor_chat)
    render json: { response: response, credits_remaining: current_learner.reload.credits }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def voice
    return render json: { error: "Không đủ credit." }, status: :payment_required unless current_learner.credits >= CREDIT_COST

    message  = params[:message].to_s.strip
    history  = Array(params[:history]).last(10)
    context  = params[:context].to_s.strip

    system_prompt = <<~PROMPT
      You are a friendly voice AI Tutor — give short, natural spoken answers (2-3 sentences max).
      - NO markdown, bullets, bold, headers — plain prose only.
      - ALWAYS reply in the same language the learner is speaking.
      #{context.present? ? "Context: #{context.truncate(300)}" : ""}
    PROMPT

    messages = history.map { |m| { role: m["role"], content: m["content"].to_s.truncate(1000) } }
    messages << { role: "user", content: message }

    svc   = ClaudeService.for_feature("ai_tutor", timeout: 30)
    reply = svc.call(system_prompt: system_prompt, messages: messages, max_tokens: 300)
    current_learner.deduct_credits!(CREDIT_COST)
    render json: { reply: reply, credits_remaining: current_learner.reload.credits }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def tts_voices
    svc = ElevenLabsService.new
    render json: svc.voices
  rescue => e
    render json: { error: e.message }, status: :service_unavailable
  end

  def tts_generate
    return render json: { error: "Không đủ credit.", credits_remaining: current_learner.credits }, status: :payment_required unless current_learner.credits >= TTS_CREDIT_COST

    text = params[:text].to_s.strip
    return render json: { error: "Nội dung trống" }, status: :unprocessable_entity if text.blank?
    return render json: { error: "Văn bản quá dài" }, status: :unprocessable_entity if text.length > 5000

    voice_id   = params[:voice_id].presence || ElevenLabsService::DEFAULT_VOICE
    model      = params[:model].presence    || "eleven_turbo_v2_5"
    speed      = (params[:speed].presence      || 1.0).to_f.clamp(0.7, 1.2)
    stability  = (params[:stability].presence  || 0.5).to_f.clamp(0.0, 1.0)
    similarity = (params[:similarity].presence || 0.75).to_f.clamp(0.0, 1.0)
    style      = (params[:style].presence      || 0.0).to_f.clamp(0.0, 1.0)
    lang_code  = params[:language_code].presence  # flash v2.5 uses this to lock pronunciation

    svc   = ElevenLabsService.new
    audio = svc.text_to_speech(text: text, voice_id: voice_id, model: model,
                               speed: speed, stability: stability,
                               similarity: similarity, style: style,
                               language_code: lang_code)

    current_learner.deduct_credits!(TTS_CREDIT_COST)
    remaining = current_learner.reload.credits

    # Return audio as base64 so we can include credits_remaining in JSON
    encoded = Base64.strict_encode64(audio)
    render json: { audio_base64: encoded, credits_remaining: remaining }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def stt_chunk
    return render json: { error: "Không đủ credit.", credits_remaining: current_learner.credits }, status: :payment_required unless current_learner.credits >= STT_CREDIT_COST

    blob = params[:chunk]
    return render json: { error: "Không có dữ liệu âm thanh" }, status: :unprocessable_entity unless blob.present?

    tmp = Tempfile.new(["stt", ".webm"])
    tmp.binmode
    tmp.write(blob.read)
    tmp.rewind

    svc    = ElevenLabsService.new
    result = svc.speech_to_text(audio_io: tmp, filename: "chunk.webm")

    current_learner.deduct_credits!(STT_CREDIT_COST)
    render json: { text: result[:text], credits_remaining: current_learner.reload.credits }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  ensure
    tmp&.close; tmp&.unlink
  end

  private

  def build_system_prompt(context)
    <<~PROMPT
      You are a friendly AI Learning Tutor for VOX platform. Help learners understand concepts clearly.
      - Reply in the same language the learner uses (Vietnamese or English).
      - Use markdown for formatting: **bold**, *italic*, bullet lists, code blocks.
      - Keep answers helpful and structured.
      - IMPORTANT: VOX can read your answers aloud (text-to-speech) and also has a live voice-call mode. So you are NOT a text-only assistant. If the learner asks about hearing you or speaking, tell them to tap the "Tự đọc" (auto-read) toggle to hear replies, or use the voice-call button (the orb) to talk with you by voice. Never claim you cannot speak.
      #{context.present? ? "Learning context: #{context.truncate(500)}" : ""}
    PROMPT
  end
end
