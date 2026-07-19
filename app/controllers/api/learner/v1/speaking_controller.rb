class Api::Learner::V1::SpeakingController < Api::Learner::V1::BaseController
  CREDIT_COST = 1

  SCENARIOS = {
    "free"       => "Trò chuyện tự do về bất kỳ chủ đề nào",
    "restaurant" => "Gọi món ở nhà hàng",
    "interview"  => "Phỏng vấn xin việc",
    "travel"     => "Hỏi đường / du lịch",
    "shopping"   => "Mua sắm",
    "smalltalk"  => "Giao tiếp xã giao hằng ngày"
  }.freeze

  LANGS = {
    "en" => "English", "vi" => "Vietnamese", "ja" => "Japanese",
    "ko" => "Korean",  "zh" => "Chinese",    "fr" => "French"
  }.freeze

  def reply
    lang_code = params[:language].to_s
    lang      = LANGS[lang_code] || "English"
    scenario  = SCENARIOS[params[:scenario].to_s] || SCENARIOS["free"]
    message   = params[:message].to_s.strip
    history   = Array(params[:history]).last(12)

    return render json: { error: "Nội dung trống" }, status: :unprocessable_entity if message.blank?

    first_turn = history.empty?
    if first_turn
      return render json: { error: "Không đủ credit." }, status: :payment_required unless current_learner.credits >= CREDIT_COST
      start_free_tts_session!(:sp_active)
    end

    system_prompt = <<~P
      You are a friendly #{lang} conversation partner helping a learner practice speaking.
      Scenario: #{scenario}.
      Rules:
      - Reply ONLY in #{lang}, in natural spoken style (1-2 short sentences).
      - Keep the conversation going by asking a simple follow-up question.
      - Match the learner's level; keep vocabulary approachable.
      - NO markdown, NO translations, NO explanations — just your spoken reply.
    P

    messages = history.map { |m| { role: m["role"], content: m["content"].to_s.truncate(500) } }
    messages << { role: "user", content: message }

    svc   = ClaudeService.for_feature("ai_tutor", timeout: 25)
    reply = svc.call(system_prompt: system_prompt, messages: messages, max_tokens: 200)

    current_learner.deduct_credits!(CREDIT_COST) if first_turn
    LearnerGamification.record!(current_learner, :speaking_turn)

    render json: { reply: reply.strip, credits_remaining: current_learner.reload.credits }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def finish
    lang_code  = params[:language].to_s
    lang       = LANGS[lang_code] || "English"
    history    = Array(params[:history])
    user_turns = history.count { |m| m["role"] == "user" }

    return render json: { error: "Chưa có hội thoại nào." }, status: :unprocessable_entity if user_turns.zero?

    convo = history.map { |m| "#{m['role'] == 'user' ? 'Learner' : 'AI'}: #{m['content']}" }.join("\n")

    system_prompt = <<~P
      You are a #{lang} speaking examiner. Evaluate the learner's spoken turns in this conversation.
      Give an encouraging, constructive assessment in VIETNAMESE.
      Return ONLY valid JSON:
      {"score": <0-100 integer>, "feedback": "<2-4 câu nhận xét bằng tiếng Việt: điểm tốt, lỗi ngữ pháp/từ vựng, gợi ý cải thiện>"}
    P

    svc  = ClaudeService.for_feature("ai_tutor", timeout: 30)
    raw  = svc.call(system_prompt: system_prompt, messages: [{ role: "user", content: convo }], max_tokens: 400)
    data = (JSON.parse(raw.match(/\{[\s\S]*\}/)[0]) rescue { "score" => nil, "feedback" => raw.to_s.truncate(400) })

    end_free_tts_session!(:sp_active)
    sp_session = current_learner.learner_speaking_sessions.create!(
      language: params[:language].to_s.presence || "en",
      scenario: params[:scenario].to_s.presence || "free",
      turns:    user_turns,
      score:    data["score"],
      feedback: data["feedback"].to_s,
      history:  history.map { |m| { role: m["role"], content: m["content"].to_s.truncate(1000) } }
    )

    render json: {
      score:      sp_session.score,
      feedback:   sp_session.feedback,
      turns:      sp_session.turns,
      session_id: sp_session.id
    }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def sessions
    list = current_learner.learner_speaking_sessions
                          .order(created_at: :desc)
                          .limit(10)
    render json: list.map { |s|
      {
        id:         s.id,
        language:   s.language,
        scenario:   s.scenario,
        turns:      s.turns,
        score:      s.score,
        feedback:   s.feedback,
        created_at: s.created_at.strftime("%d/%m %H:%M")
      }
    }
  end

  def transcript
    session = current_learner.learner_speaking_sessions.find(params[:id])
    render json: {
      id:         session.id,
      language:   session.language,
      scenario:   session.scenario,
      turns:      session.turns,
      score:      session.score,
      feedback:   session.feedback,
      created_at: session.created_at.strftime("%d/%m/%Y %H:%M"),
      history:    Array(session.history).map { |m| { role: m["role"], content: m["content"] } }
    }
  end
end
