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

  # Returns raw audio bytes (mp3)
  def text_to_speech(text:, voice_id: DEFAULT_VOICE, model: "eleven_multilingual_v2", stability: 0.5, similarity: 0.75)
    response = HTTParty.post(
      "#{BASE_URL}/v1/text-to-speech/#{voice_id}",
      headers: default_headers.merge("Accept" => "audio/mpeg"),
      body: {
        text:          text,
        model_id:      model,
        voice_settings: {
          stability:        stability,
          similarity_boost: similarity
        }
      }.to_json,
      timeout: 60
    )

    unless response.success?
      body = response.body rescue ""
      raise "ElevenLabs TTS error #{response.code}: #{body.truncate(200)}"
    end

    response.body
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
end
