class Learner::ToolsController < Learner::BaseController
  SUMMARIZE_COST = 2

  def tts
    @has_tts = ENV["ELEVENLABS_API_KEY"].present?
  end

  def stt
    @has_stt = ENV["ELEVENLABS_API_KEY"].present?
  end

  def summarize; end

  def translate
    return render json: { error: "Không đủ credit." }, status: :payment_required unless current_learner.credits >= 1

    text        = params[:text].to_s.strip
    target_lang = params[:target_lang].to_s.strip.presence || "Vietnamese"
    return render json: { error: "Nội dung trống" } if text.blank?

    svc    = ClaudeService.for_feature("ai_tutor", timeout: 20)
    result = svc.call(
      system_prompt: "You are a precise translator. Translate the given text to #{target_lang}. Return ONLY the translated text, no explanations, no quotes.",
      messages: [{ role: "user", content: text }],
      max_tokens: 600
    )

    current_learner.deduct_credits!(1)
    render json: { translated: result.strip, credits_remaining: current_learner.reload.credits }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def punctuate
    text = params[:text].to_s.strip
    return render json: { punctuated: text } if text.blank?

    svc    = ClaudeService.for_feature("ai_tutor", timeout: 15)
    result = svc.call(
      system_prompt: "Add proper punctuation and capitalization to this text. Preserve every word exactly — only add or fix punctuation marks and capitalize sentence starts. Return ONLY the corrected text.",
      messages: [{ role: "user", content: text }],
      max_tokens: 1000
    )
    render json: { punctuated: result.strip }
  rescue => e
    render json: { punctuated: text }
  end

  def do_summarize
    return render json: { error: "Không đủ credit." }, status: :payment_required unless current_learner.credits >= SUMMARIZE_COST

    prompt = params[:prompt].to_s.strip
    files  = Array(params[:files])

    # Build content parts
    parts = []
    parts << { type: "text", text: prompt } if prompt.present?

    files.each do |f|
      next unless f.respond_to?(:content_type)
      if f.content_type.start_with?("image/")
        data = Base64.strict_encode64(f.read)
        parts << { type: "image", source: { type: "base64", media_type: f.content_type, data: data } }
      else
        text = f.read.force_encoding("UTF-8").scrub.truncate(20_000)
        parts << { type: "text", text: "File (#{f.original_filename}):\n#{text}" }
      end
    end

    return render json: { error: "Vui lòng nhập nội dung hoặc đính kèm file." } if parts.empty?

    system_prompt = <<~P
      You are a document summarizer. Summarize the given content clearly and concisely.
      - Reply in Vietnamese unless the content is clearly in another language.
      - Use markdown: headings (##), bullet points, **bold** for key points.
      - At the very end, add a line: TITLE: <một tiêu đề ngắn gọn cho tóm tắt này>
    P

    svc    = ClaudeService.for_feature("ai_tutor", timeout: 45)
    result = svc.call(system_prompt: system_prompt, messages: [{ role: "user", content: parts }], max_tokens: 1500)

    # Extract title
    title = result[/TITLE:\s*(.+)$/i, 1]&.strip || "Tóm tắt #{Time.current.strftime('%d/%m %H:%M')}"
    body  = result.sub(/\n?TITLE:.*$/i, "").strip

    current_learner.deduct_credits!(SUMMARIZE_COST)
    render json: { summary: body, title: title, credits_remaining: current_learner.reload.credits }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
