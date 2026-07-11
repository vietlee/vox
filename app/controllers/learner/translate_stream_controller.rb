require 'net/http'

class Learner::TranslateStreamController < Learner::BaseController
  include ActionController::Live

  # Delimits the trailing credit balance from the translated text.
  CREDITS_SENTINEL = "".freeze

  LANG_CODES = {
    "vietnamese" => "vi", "english" => "en", "japanese" => "ja",
    "chinese"    => "zh-CN", "korean" => "ko", "french" => "fr",
    "german"     => "de",  "spanish" => "es", "thai"    => "th"
  }.freeze

  # Uses Google Translate (unofficial client=gtx endpoint) instead of Claude so
  # translation responds in ~100ms rather than ~500ms, matching the live transcript speed.
  # Realtime STT sends free "interim" previews as the user speaks; only finalized
  # sentences (final=true) cost 1 credit.
  def create
    text        = params[:text].to_s.strip
    target_code = params[:target_code].to_s.strip.presence ||
                  LANG_CODES[params[:target_lang].to_s.downcase] || "vi"
    is_final    = params[:final].to_s == "true"

    response.headers["Content-Type"]      = "text/plain; charset=utf-8"
    response.headers["Cache-Control"]     = "no-cache, no-store"
    response.headers["X-Accel-Buffering"] = "no"

    if text.present? && current_learner.credits >= 1
      translated = google_translate(text, target_code)
      response.stream.write(translated)

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

  private

  def google_translate(text, target_code)
    uri = URI("https://translate.googleapis.com/translate_a/single")
    uri.query = URI.encode_www_form(
      client: "gtx", sl: "auto", tl: target_code, dt: "t", q: text
    )
    http = Net::HTTP.new(uri.host, 443)
    http.use_ssl      = true
    http.open_timeout = 4
    http.read_timeout = 6
    res  = http.get(uri.request_uri, "User-Agent" => "Mozilla/5.0")
    data = JSON.parse(res.body)
    data[0]&.map { |chunk| chunk&.first }&.compact&.join || ""
  rescue => e
    Rails.logger.warn "[TranslateStream] Google Translate failed: #{e.message}"
    ""
  end
end
