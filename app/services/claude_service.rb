class ClaudeService
  HAIKU_MODEL  = "claude-haiku-4-5-20251001"
  SONNET_MODEL = "claude-sonnet-4-6"
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

    JSON.parse(response.body).dig("content", 0, "text")
  rescue => e
    Rails.logger.error "ClaudeService error: #{e.message}"
    raise
  end

  def self.haiku     = new(model: HAIKU_MODEL)
  def self.sonnet    = new(model: SONNET_MODEL, timeout: 90)
  def self.sonnet_long = new(model: SONNET_MODEL, timeout: 180)
end
