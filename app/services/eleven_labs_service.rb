class ElevenLabsService
  BASE_URL = "https://api.elevenlabs.io"
  DEFAULT_VOICE = "EXAVITQu4vr4xnSDxMaL" # Rachel — natural, clear English/multilingual

  # Structured error so callers can branch on code without parsing strings
  # Codes: :auth_error | :rate_limited | :invalid_data | :server_error | :network_error | :timeout
  class Error < StandardError
    attr_reader :code, :http_status, :detail
    def initialize(message, code: :server_error, http_status: nil, detail: nil)
      super(message)
      @code        = code
      @http_status = http_status
      @detail      = detail
    end
  end

  def initialize
    @api_key = ENV["ELEVENLABS_API_KEY"]
    raise "ELEVENLABS_API_KEY is not set" if @api_key.blank?
  end

  # Returns ElevenLabs account usage: { tier:, used:, limit:, remaining:, pct: }
  def subscription_usage
    response = HTTParty.get(
      "#{BASE_URL}/v1/user/subscription",
      headers: default_headers,
      timeout: 10
    )
    unless response.success?
      parsed = JSON.parse(response.body) rescue {}
      msg = parsed.dig("detail", "message") || "HTTP #{response.code}"
      raise "ElevenLabs subscription error: #{msg}"
    end

    data      = JSON.parse(response.body)
    used      = data["character_count"].to_i
    limit     = data["character_limit"].to_i
    remaining = [limit - used, 0].max
    pct       = limit > 0 ? (used.to_f / limit * 100).round(1) : 0

    {
      tier:      data["tier"] || "unknown",
      used:      used,
      limit:     limit,
      remaining: remaining,
      pct:       pct,
      next_reset: data["next_character_count_reset_unix"]
    }
  rescue => e
    Rails.logger.error "ElevenLabsService#subscription_usage error: #{e.message} (#{e.class})"
    nil
  end

  # Returns an array of voice hashes: { id:, name:, preview_url:, category: }
  def voices
    response = HTTParty.get(
      "#{BASE_URL}/v1/voices",
      headers: default_headers,
      timeout: 15
    )
    raise "ElevenLabs voices error: #{response.code}" unless response.success?

    parsed = JSON.parse(response.body)
    parsed["voices"].reject { |v| v["category"] == "premade" }.map do |v|
      {
        id:          v["voice_id"],
        name:        v["name"],
        preview_url: v["preview_url"],
        category:    v["category"] || "custom"
      }
    end
  rescue => e
    Rails.logger.error "ElevenLabsService#voices error: #{e.message}"
    raise
  end

  # Returns raw audio bytes (mp3). Auto-retries on 429 and 5xx (transient errors).
  # speed: ElevenLabs voice_settings supports 0.7–1.2 (Flash v2.5, v3, Multilingual v2)
  def text_to_speech(text:, voice_id: DEFAULT_VOICE, model: "eleven_turbo_v2_5", speed: 1.0, stability: 0.5, similarity: 0.75, style: 0.0, output_format: "mp3_44100_128")
    max_attempts = 3

    payload = {
      text:     text,
      model_id: model,
      voice_settings: {
        stability:         stability.to_f,
        similarity_boost:  similarity.to_f,
        style:             style.to_f,
        use_speaker_boost: true,
        speed:             speed.to_f.clamp(0.7, 1.2)
      }
    }.to_json

    Rails.logger.info "ElevenLabs TTS start: model=#{model} voice=#{voice_id} chars=#{text.length}"

    max_attempts.times do |attempt|
      begin
        response = HTTParty.post(
          "#{BASE_URL}/v1/text-to-speech/#{voice_id}?output_format=#{output_format}",
          headers: default_headers.merge("Accept" => "audio/mpeg"),
          body:    payload,
          timeout: 300
        )

        if response.success?
          Rails.logger.info "ElevenLabs TTS ok (attempt #{attempt + 1}), #{response.body.bytesize} bytes"
          return response.body
        end

        log_http_error(response, attempt, max_attempts)

        retryable = [429, 500, 502, 503, 504].include?(response.code)
        if retryable && attempt < max_attempts - 1
          sleep (attempt + 1) * 2
          next
        end

        raise build_http_error(response)

      rescue ElevenLabsService::Error
        raise  # already structured — don't wrap again

      rescue Timeout::Error, Net::ReadTimeout, Net::OpenTimeout => e
        log_network_error(e, attempt, max_attempts)
        raise ElevenLabsService::Error.new(
          "ElevenLabs không phản hồi (timeout). Vui lòng thử lại.",
          code: :timeout
        ) if attempt >= max_attempts - 1
        sleep (attempt + 1) * 2

      rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
        log_network_error(e, attempt, max_attempts)
        raise ElevenLabsService::Error.new(
          "Không thể kết nối ElevenLabs (#{e.class.name.demodulize}). Vui lòng thử lại.",
          code: :network_error
        ) if attempt >= max_attempts - 1
        sleep (attempt + 1) * 2
      end
    end
  rescue ElevenLabsService::Error => e
    Rails.logger.error "ElevenLabsService#text_to_speech failed [#{e.code}] #{e.message}"
    raise
  rescue => e
    Rails.logger.error "ElevenLabsService#text_to_speech unexpected error: #{e.message} (#{e.class})"
    raise
  end

  private

  def default_headers
    {
      "xi-api-key"   => @api_key,
      "Content-Type" => "application/json"
    }
  end

  def log_http_error(response, attempt, max_attempts)
    body_snippet = response.body.to_s.slice(0, 300).gsub(/\s+/, " ")
    Rails.logger.warn(
      "ElevenLabs HTTP #{response.code} " \
      "(attempt #{attempt + 1}/#{max_attempts}): #{body_snippet}"
    )
  end

  def log_network_error(err, attempt, max_attempts)
    Rails.logger.warn(
      "ElevenLabs #{err.class.name.demodulize} " \
      "(attempt #{attempt + 1}/#{max_attempts}): #{err.message}"
    )
  end

  def build_http_error(response)
    parsed = JSON.parse(response.body) rescue {}
    detail = parsed.dig("detail", "message") || parsed["detail"] || parsed["message"]

    case response.code
    when 401
      ElevenLabsService::Error.new(
        "API key không hợp lệ. Kiểm tra lại ELEVENLABS_API_KEY.",
        code: :auth_error, http_status: 401, detail: detail
      )
    when 429
      ElevenLabsService::Error.new(
        "ElevenLabs đang quá tải (rate limit). Vui lòng thử lại sau ít phút.",
        code: :rate_limited, http_status: 429, detail: detail
      )
    when 422
      ElevenLabsService::Error.new(
        "Dữ liệu không hợp lệ: #{detail || 'unknown'}",
        code: :invalid_data, http_status: 422, detail: detail
      )
    else
      ElevenLabsService::Error.new(
        "ElevenLabs lỗi #{response.code}: #{detail || 'Vui lòng thử lại.'}",
        code: :server_error, http_status: response.code, detail: detail
      )
    end
  end
end
