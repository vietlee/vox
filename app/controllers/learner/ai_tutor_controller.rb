class Learner::AiTutorController < Learner::BaseController
  CREDIT_COST = 1

  def index
    @context = params[:context] # quiz/flashcard/path context passed from assignment pages
  end

  def chat
    unless current_learner.credits >= CREDIT_COST
      return render json: { error: "Không đủ credit. Vui lòng mua thêm." }, status: :payment_required
    end

    message = params[:message].to_s.strip
    context = params[:context].to_s.strip
    return render json: { error: "Tin nhắn trống" }, status: :unprocessable_entity if message.blank?

    system_prompt = <<~PROMPT
      You are a friendly AI Learning Tutor. Help learners understand concepts clearly.
      - Reply in the same language the learner uses (Vietnamese or English).
      - Keep answers concise (2-4 sentences for chat, longer if asked to explain deeply).
      - NO markdown bullets or headers — plain conversational text only.
      #{context.present? ? "Learning context: #{context.truncate(500)}" : ""}
    PROMPT

    svc = ClaudeService.for_feature("ai_tutor", timeout: 30)
    response = svc.call(system_prompt: system_prompt, user_prompt: message, max_tokens: 1000)

    current_learner.deduct_credits!(CREDIT_COST)
    render json: { reply: response, credits_remaining: current_learner.reload.credits }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def voice
    unless current_learner.credits >= CREDIT_COST
      return render json: { error: "Không đủ credit." }, status: :payment_required
    end

    message = params[:message].to_s.strip
    context = params[:context].to_s.strip

    system_prompt = <<~PROMPT
      You are a friendly voice AI Tutor — give short, natural spoken answers (2-3 sentences max).
      - NO markdown, bullets, bold, headers — plain prose only.
      - ALWAYS reply in the same language the learner is speaking.
      #{context.present? ? "Context: #{context.truncate(300)}" : ""}
    PROMPT

    svc = ClaudeService.for_feature("ai_tutor", timeout: 30)
    response = svc.call(system_prompt: system_prompt, user_prompt: message, max_tokens: 300)

    current_learner.deduct_credits!(CREDIT_COST)
    render json: { reply: response, credits_remaining: current_learner.reload.credits }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
