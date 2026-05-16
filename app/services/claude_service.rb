class ClaudeService
  HAIKU_MODEL  = "claude-haiku-4-5-20251001"
  SONNET_MODEL = "claude-sonnet-4-6"
  API_URL      = "https://api.anthropic.com/v1/messages"

  def initialize(model: HAIKU_MODEL)
    @model = model
    @api_key = ENV["ANTHROPIC_API_KEY"]
  end

  def call(system_prompt:, user_prompt:, max_tokens: 2048)
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
        messages: [{ role: "user", content: user_prompt }]
      }.to_json,
      timeout: 60
    )

    raise "Claude API error: #{response.body}" unless response.success?

    JSON.parse(response.body).dig("content", 0, "text")
  rescue => e
    Rails.logger.error "ClaudeService error: #{e.message}"
    raise
  end

  def self.haiku  = new(model: HAIKU_MODEL)
  def self.sonnet = new(model: SONNET_MODEL)
end
