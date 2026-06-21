class ClaudeService
  HAIKU_MODEL  = "claude-haiku-4-5-20251001"
  SONNET_MODEL = "claude-sonnet-4-6"
  SONNET_45    = "claude-sonnet-4-5"
  OPUS_MODEL   = "claude-opus-4-5"
  OPUS_48      = "claude-opus-4-8"
  API_URL      = "https://api.anthropic.com/v1/messages"

  def initialize(model: HAIKU_MODEL, timeout: 90)
    @model   = model
    @api_key = ENV["ANTHROPIC_API_KEY"]
    @timeout = timeout
  end

  def call(system_prompt:, user_prompt: nil, messages: nil, max_tokens: 2048)
    actual_messages = messages || [{ role: "user", content: user_prompt }]
    response = HTTParty.post(API_URL,
      headers: {
        "x-api-key"         => @api_key,
        "anthropic-version" => "2023-06-01",
        "content-type"      => "application/json"
      },
      body: {
        model: @model,
        max_tokens: max_tokens,
        system: system_prompt,
        messages: actual_messages
      }.to_json,
      timeout: @timeout
    )

    raise "Claude API error: #{response.body}" unless response.success?

    parsed = JSON.parse(response.body)
    stop_reason = parsed["stop_reason"]
    Rails.logger.warn "ClaudeService: stop_reason=#{stop_reason}" if stop_reason != "end_turn"
    parsed.dig("content", 0, "text")
  rescue => e
    Rails.logger.error "ClaudeService error: #{e.message}"
    raise
  end

  # Returns { text: String, truncated: Boolean }
  def call_full(system_prompt:, user_prompt: nil, messages: nil, max_tokens: 2048)
    actual_messages = messages || [{ role: "user", content: user_prompt }]
    response = HTTParty.post(API_URL,
      headers: {
        "x-api-key"         => @api_key,
        "anthropic-version" => "2023-06-01",
        "content-type"      => "application/json"
      },
      body: {
        model: @model,
        max_tokens: max_tokens,
        system: system_prompt,
        messages: actual_messages
      }.to_json,
      timeout: @timeout
    )

    raise "Claude API error: #{response.body}" unless response.success?

    parsed      = JSON.parse(response.body)
    stop_reason = parsed["stop_reason"]
    truncated   = (stop_reason == "max_tokens")
    Rails.logger.warn "ClaudeService: stop_reason=#{stop_reason} (TRUNCATED)" if truncated
    { text: parsed.dig("content", 0, "text").to_s, truncated: truncated }
  rescue => e
    Rails.logger.error "ClaudeService error: #{e.message}"
    raise
  end

  def self.haiku       = new(model: HAIKU_MODEL)
  def self.sonnet      = new(model: SONNET_MODEL, timeout: 90)
  def self.sonnet_long = new(model: SONNET_MODEL, timeout: 240)
  def self.opus        = new(model: OPUS_MODEL, timeout: 180)
  def self.opus_long   = new(model: OPUS_MODEL, timeout: 360)

  # Resolve model from admin config, fallback to default
  def self.for_feature(feature_key, timeout: 120)
    model_id = AiModelConfig.model_for(feature_key)
    new(model: model_id, timeout: timeout)
  end
end
