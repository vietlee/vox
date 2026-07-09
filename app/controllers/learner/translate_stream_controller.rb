class Learner::TranslateStreamController < Learner::BaseController
  include ActionController::Live

  # Delimits the trailing credit balance from the streamed translation text.
  CREDITS_SENTINEL = "".freeze # EOT control char, won't appear in translations

  # Streams the translation token-by-token (Claude Haiku streaming) so the
  # translated text appears in real time, matching the live transcript. Realtime
  # STT sends many free "interim" previews as the user speaks; only finalized
  # sentences (final=true) cost 1 credit. A trailing sentinel carries the updated
  # credit balance so the UI can refresh it.
  def create
    text        = params[:text].to_s.strip
    target_lang = params[:target_lang].to_s.strip.presence || "Vietnamese"
    is_final    = params[:final].to_s == "true"

    response.headers["Content-Type"]      = "text/plain; charset=utf-8"
    response.headers["Cache-Control"]     = "no-cache, no-store"
    response.headers["X-Accel-Buffering"] = "no"

    if text.present? && current_learner.credits >= 1
      svc = ClaudeService.haiku
      svc.stream_call(
        system_prompt: "You are a precise translator. Translate the given text to #{target_lang}. Return ONLY the translated text, no explanations, no quotes, no notes.",
        messages: [{ role: "user", content: text }],
        max_tokens: 300
      ) do |chunk|
        response.stream.write(chunk)
      end

      if is_final
        current_learner.deduct_credits!(1)
        response.stream.write("#{CREDITS_SENTINEL}#{current_learner.reload.credits}")
      end
    end
  rescue => e
    Rails.logger.error "[TranslateStream] #{e.class}: #{e.message}"
  ensure
    response.stream.close rescue nil
  end
end
