class ElevenLabsService
  BASE_URL = "https://api.elevenlabs.io"
  DEFAULT_VOICE = "EXAVITQu4vr4xnSDxMaL" # Rachel — natural, clear English/multilingual

  def initialize
    @api_key = ENV["ELEVENLABS_API_KEY"]
    raise "ELEVENLABS_API_KEY is not set" if @api_key.blank?
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
    parsed["voices"].map do |v|
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

  # Returns raw audio bytes (mp3). Auto-retries on 429.
  def text_to_speech(text:, voice_id: DEFAULT_VOICE, model: "eleven_multilingual_v2", stability: 0.5, similarity: 0.75, style: 0.0, output_format: "mp3_44100_192")
    max_attempts = 3
    payload = {
      text:     text,
      model_id: model,
      voice_settings: {
        stability:         stability.to_f,
        similarity_boost:  similarity.to_f,
        style:             style.to_f,
        use_speaker_boost: true
      }
    }.to_json

    max_attempts.times do |attempt|
      response = HTTParty.post(
        "#{BASE_URL}/v1/text-to-speech/#{voice_id}?output_format=#{output_format}",
        headers: default_headers.merge("Accept" => "audio/mpeg"),
        body:    payload,
        timeout: 60
      )

      if response.code == 429 && attempt < max_attempts - 1
        wait = (attempt + 1) * 3
        Rails.logger.warn "ElevenLabs 429, retry in #{wait}s (#{attempt + 1}/#{max_attempts})"
        sleep wait
        next
      end

      raise friendly_error(response) unless response.success?
      return response.body
    end
  rescue HTTParty::Error, Timeout::Error
    raise "Không thể kết nối ElevenLabs. Vui lòng thử lại sau."
  rescue => e
    Rails.logger.error "ElevenLabsService#text_to_speech error: #{e.message}"
    raise
  end

  private

  def default_headers
    {
      "xi-api-key"   => @api_key,
      "Content-Type" => "application/json"
    }
  end

  def friendly_error(response)
    parsed = JSON.parse(response.body) rescue {}
    detail = parsed.dig("detail", "message") || parsed["detail"] || parsed["message"]

    case response.code
    when 401 then "API key không hợp lệ. Vui lòng kiểm tra lại ELEVENLABS_API_KEY."
    when 429 then "ElevenLabs đang quá tải. Vui lòng thử lại sau ít phút."
    when 422 then "Dữ liệu không hợp lệ: #{detail || 'unknown'}"
    else "ElevenLabs lỗi #{response.code}: #{detail || 'Vui lòng thử lại.'}"
    end
  end
end
