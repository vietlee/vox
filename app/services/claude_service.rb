class ClaudeService
  HAIKU_MODEL  = "claude-haiku-4-5-20251001"
  SONNET_MODEL = "claude-sonnet-4-6"
  SONNET_45    = "claude-sonnet-4-5"
  OPUS_MODEL   = "claude-opus-4-5"
  OPUS_48      = "claude-opus-4-8"
  API_URL      = "https://api.anthropic.com/v1/messages"

  # Token usage from the most recent call — used by AiTokenPricing to bill
  # conversational features by real length. `input` excludes cache-read tokens
  # (the API reports re-sent, cached history under a separate field), so when
  # `cache:` is on these reflect only the fresh question + answer of the turn.
  attr_reader :last_input_tokens, :last_output_tokens

  def initialize(model: HAIKU_MODEL, timeout: 90)
    @model   = model
    @api_key = ENV["ANTHROPIC_API_KEY"]
    @timeout = timeout
    @last_input_tokens  = 0
    @last_output_tokens = 0
  end

  # `cache: true` marks the system prompt and the conversation prefix with
  # ephemeral cache_control, so multi-turn chats re-send history as cheap cache
  # reads instead of full-price input. Recommended for AI Chat / Tutor.
  def call(system_prompt:, user_prompt: nil, messages: nil, max_tokens: 2048, cache: false)
    actual_messages = messages || [{ role: "user", content: user_prompt }]
    response = HTTParty.post(API_URL,
      headers: {
        "x-api-key"         => @api_key,
        "anthropic-version" => "2023-06-01",
        "content-type"      => "application/json"
      },
      body: build_body(system_prompt, actual_messages, max_tokens, cache).to_json,
      timeout: @timeout
    )

    raise "Claude API error: #{response.body}" unless response.success?

    parsed = JSON.parse(response.body)
    stop_reason = parsed["stop_reason"]
    record_usage(parsed["usage"])
    Rails.logger.info "ClaudeService: model=#{@model} stop_reason=#{stop_reason} in=#{@last_input_tokens} out=#{@last_output_tokens} max=#{max_tokens}"
    parsed.dig("content", 0, "text")
  rescue => e
    Rails.logger.error "ClaudeService error: #{e.message}"
    raise
  end

  # Returns { text: String, truncated: Boolean }
  def call_full(system_prompt:, user_prompt: nil, messages: nil, max_tokens: 2048, cache: false)
    actual_messages = messages || [{ role: "user", content: user_prompt }]
    response = HTTParty.post(API_URL,
      headers: {
        "x-api-key"         => @api_key,
        "anthropic-version" => "2023-06-01",
        "content-type"      => "application/json"
      },
      body: build_body(system_prompt, actual_messages, max_tokens, cache).to_json,
      timeout: @timeout
    )

    raise "Claude API error: #{response.body}" unless response.success?

    parsed      = JSON.parse(response.body)
    stop_reason = parsed["stop_reason"]
    truncated   = (stop_reason == "max_tokens")
    record_usage(parsed["usage"])
    Rails.logger.warn "ClaudeService: stop_reason=#{stop_reason} (TRUNCATED)" if truncated
    { text: parsed.dig("content", 0, "text").to_s, truncated: truncated }
  rescue => e
    Rails.logger.error "ClaudeService error: #{e.message}"
    raise
  end

  # Streams text deltas to a block, returns full accumulated text
  def stream_call(system_prompt:, messages:, max_tokens: 200, cache: false, &block)
    require 'net/http'
    uri  = URI(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl     = true
    http.read_timeout = @timeout

    req = Net::HTTP::Post.new(uri)
    req['x-api-key']         = @api_key
    req['anthropic-version'] = '2023-06-01'
    req['content-type']      = 'application/json'
    req.body = build_body(system_prompt, messages, max_tokens, cache, stream: true).to_json

    full_text = ''
    http.request(req) do |resp|
      resp.read_body do |raw|
        raw.each_line do |line|
          next unless line.start_with?('data: ')
          data = JSON.parse(line[6..].strip) rescue next
          case data['type']
          when 'message_start'
            @last_input_tokens = data.dig('message', 'usage', 'input_tokens').to_i
          when 'message_delta'
            # Final cumulative output-token count for the streamed message.
            out = data.dig('usage', 'output_tokens')
            @last_output_tokens = out.to_i if out
          when 'content_block_delta'
            text = data.dig('delta', 'text').to_s
            next if text.empty?
            full_text += text
            block.call(text)
          end
        end
      end
    end
    full_text
  rescue => e
    Rails.logger.error "ClaudeService#stream_call: #{e.message}"
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

  private

  def record_usage(usage)
    return unless usage
    @last_input_tokens  = usage["input_tokens"].to_i
    @last_output_tokens = usage["output_tokens"].to_i
  end

  # Builds the request body, optionally adding ephemeral cache_control to the
  # system prompt and the conversation prefix (the last message), so repeated
  # multi-turn context is billed as cache reads instead of full input.
  def build_body(system_prompt, messages, max_tokens, cache, stream: false)
    body = {
      model:      @model,
      max_tokens: max_tokens,
      system:     cache ? [{ type: "text", text: system_prompt.to_s, cache_control: { type: "ephemeral" } }] : system_prompt,
      messages:   cache ? cache_prefix(messages) : messages
    }
    body[:stream] = true if stream
    body
  end

  # Marks the last message's content with cache_control so everything up to and
  # including it forms a cacheable prefix. Non-destructive (dups the array).
  def cache_prefix(messages)
    return messages if messages.blank?
    msgs = messages.map(&:dup)
    last = msgs.last
    content = last[:content] || last["content"]
    marked =
      if content.is_a?(String)
        [{ type: "text", text: content, cache_control: { type: "ephemeral" } }]
      elsif content.is_a?(Array) && content.any?
        arr = content.map { |b| b.is_a?(Hash) ? b.dup : b }
        tail = arr.last
        arr[-1] = tail.merge(cache_control: { type: "ephemeral" }) if tail.is_a?(Hash)
        arr
      else
        content
      end
    last[:content] = marked
    last.delete("content") if last.key?("content")
    msgs
  end
end
