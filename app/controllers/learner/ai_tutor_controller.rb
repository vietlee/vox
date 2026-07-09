class Learner::AiTutorController < Learner::BaseController
  CHAT_SESSION_COST  = 2   # charged once at session start (first message)
  VOICE_SESSION_COST = 1   # charged once at call start (first turn)
  TTS_CHARS_PER_CREDIT = 200   # 1 credit per 200 chars, minimum 1
  STT_CREDIT_COST      = 2

  def index
    @context = params[:context]
    @has_tts = ENV["ELEVENLABS_API_KEY"].present?
    @has_stt = ENV["ELEVENLABS_API_KEY"].present?
  end

  def chat
    message = params[:message].to_s.strip
    history = Array(params[:history]).last(20)
    context = params[:context].to_s.strip
    return render json: { error: "Tin nhắn trống" }, status: :unprocessable_entity if message.blank?

    first_turn = history.empty?
    if first_turn
      return render json: { error: "Không đủ credit. Vui lòng mua thêm." }, status: :payment_required unless current_learner.credits >= CHAT_SESSION_COST
    end

    system_prompt = build_system_prompt(context)
    messages = history.map { |m| { role: m["role"], content: m["content"].to_s.truncate(2000) } }
    messages << { role: "user", content: message }

    svc      = ClaudeService.for_feature("ai_tutor", timeout: 30)
    response = svc.call(system_prompt: system_prompt, messages: messages, max_tokens: 1000)

    current_learner.deduct_credits!(CHAT_SESSION_COST) if first_turn
    LearnerGamification.record!(current_learner, :tutor_chat)
    render json: { response: response, credits_remaining: current_learner.reload.credits }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def voice
    message  = params[:message].to_s.strip
    history  = Array(params[:history]).last(10)
    context  = params[:context].to_s.strip

    first_turn = history.empty?
    if first_turn
      return render json: { error: "Không đủ credit." }, status: :payment_required unless current_learner.credits >= VOICE_SESSION_COST
      start_free_tts_session!(:vc_active)
    end

    system_prompt = <<~PROMPT
      You are a friendly VOICE AI Tutor in a live spoken phone-call conversation.
      - CRITICAL: You ARE speaking out loud. Every reply is read to the learner in your voice in real time. You are NOT a text assistant — never say you are "text-based", "can only type", or "cannot talk". You are literally talking with them right now.
      - Give short, natural spoken answers (2-3 sentences max), like a real phone call.
      - NO markdown, bullets, bold, headers, or emoji — plain spoken prose only.
      - ALWAYS reply in the same language the learner is speaking.
      #{context.present? ? "Context: #{context.truncate(300)}" : ""}
    PROMPT

    messages = history.map { |m| { role: m["role"], content: m["content"].to_s.truncate(1000) } }
    messages << { role: "user", content: message }

    svc   = ClaudeService.haiku
    reply = svc.call(system_prompt: system_prompt, messages: messages, max_tokens: 300)
    current_learner.deduct_credits!(VOICE_SESSION_COST) if first_turn
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
    text = params[:text].to_s.strip
    return render json: { error: "Nội dung trống" }, status: :unprocessable_entity if text.blank?
    return render json: { error: "Văn bản quá dài" }, status: :unprocessable_entity if text.length > 5000

    embedded   = in_speaking_session? || in_voice_session?
    cost       = embedded ? 0 : [(text.length.to_f / TTS_CHARS_PER_CREDIT).ceil, 1].max
    unless embedded
      return render json: { error: "Không đủ credit.", credits_remaining: current_learner.credits }, status: :payment_required unless current_learner.credits >= cost
    end

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

    current_learner.deduct_credits!(cost) if cost > 0
    remaining = current_learner.reload.credits

    encoded = Base64.strict_encode64(audio)
    render json: { audio_base64: encoded, credits_remaining: remaining, credits_cost: cost }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def stt_chunk
    embedded = in_speaking_session? || in_voice_session?
    unless embedded
      return render json: { error: "Không đủ credit.", credits_remaining: current_learner.credits }, status: :payment_required unless current_learner.credits >= STT_CREDIT_COST
    end

    blob = params[:chunk]
    return render json: { error: "Không có dữ liệu âm thanh" }, status: :unprocessable_entity unless blob.present?

    tmp = Tempfile.new(["stt", ".webm"])
    tmp.binmode
    tmp.write(blob.read)
    tmp.rewind

    svc    = ElevenLabsService.new
    result = svc.speech_to_text(audio_io: tmp, filename: "chunk.webm")

    current_learner.deduct_credits!(STT_CREDIT_COST) unless embedded
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
      - CRITICAL: You CAN speak. Every reply you write is automatically read aloud to the learner by voice (text-to-speech is ON by default), and VOX also has a live voice-call mode (the orb button) to talk with you hands-free. You are NOT a text-only assistant and must NEVER say you cannot speak, cannot use voice, or are "just text". If asked whether you can talk, confirm yes — your answers are spoken automatically, and they can tap the orb to have a full voice conversation. Answer naturally as if speaking.
      #{context.present? ? "Learning context: #{context.truncate(500)}" : ""}
    PROMPT
  end
end
