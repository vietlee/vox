require "net/http"

class AiFeedbackAnalysisJob < ApplicationJob
  queue_as :ai

  TRANSIENT_ERRORS = [Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT].freeze

  retry_on(*TRANSIENT_ERRORS, wait: 20.seconds, attempts: 2) do |job_instance, error|
    ai_job = AiJob.find_by(id: job_instance.arguments.first)
    ai_job&.fail!("Network timeout after retries: #{error.message.truncate(200)}")
  end

  def perform(job_id)
    job   = AiJob.find(job_id)
    board = FeedbackBoard.find(job.resource_id)
    job.start!

    feedbacks = board.feedbacks.approved.order(upvotes_count: :desc, created_at: :desc).limit(100)
    return job.complete!({ error: "no_data" }) if feedbacks.empty?

    language  = job.input_data&.dig("language") || board.workspace.language || "vi"
    lang_name = language == "vi" ? "Vietnamese" : "English"

    # Build structured data preserving upvote signal and recency
    feedback_data = feedbacks.map do |fb|
      {
        content:  fb.content.to_s.truncate(250),
        upvotes:  fb.upvotes_count,
        days_ago: ((Time.current - fb.created_at) / 1.day).round,
        anonymous: fb.anonymous?
      }
    end

    total_count    = board.feedbacks.approved.count
    analyzed_count = feedbacks.count
    top_upvoted    = feedback_data.select { |f| f[:upvotes] > 0 }.first(5)
    recent         = feedback_data.select { |f| f[:days_ago] <= 14 }.first(10)

    system_prompt = <<~SYSTEM
      You are a senior HR consultant and employee experience expert.
      Your job is to analyze employee feedback and turn it into leadership-ready insights that drive real action.

      Core principles:
      - Write entirely in #{lang_name}
      - Upvoted feedback represents collective sentiment — weight it more heavily than single voices
      - Recent feedback (last 14 days) reflects current pulse — flag if it differs from overall trend
      - Be specific: cite numbers, quote actual feedback, name concrete problems
      - Every recommendation must be something a manager can actually assign and track
      - Do not soften findings — if something is a serious problem, say so clearly
    SYSTEM

    user_prompt = <<~PROMPT
      Analyze employee feedback from the board: "#{board.title}"
      #{board.description.present? ? "Board description: #{board.description}" : ""}

      ## Dataset
      - Total approved feedbacks: #{total_count}
      - Analyzed in this batch: #{analyzed_count}
      #{total_count > analyzed_count ? "- Note: showing top #{analyzed_count} by upvotes + recency (#{total_count - analyzed_count} additional feedbacks not shown)" : ""}

      ## All Feedback (sorted by upvotes desc, then recent)
      #{feedback_data.map.with_index(1) { |f, i|
        upvote_label = f[:upvotes] > 0 ? " [#{f[:upvotes]} upvotes]" : ""
        recency_label = f[:days_ago] <= 7 ? " [this week]" : f[:days_ago] <= 14 ? " [this fortnight]" : ""
        "#{i}. #{f[:content]}#{upvote_label}#{recency_label}"
      }.join("\n")}

      #{top_upvoted.any? ? "## Most Upvoted (community-validated concerns)\n#{top_upvoted.map { |f| "• [#{f[:upvotes]} votes] #{f[:content]}" }.join("\n")}" : ""}

      #{recent.any? && recent.count < analyzed_count ? "## Recent Feedback (last 14 days — #{recent.count} entries)\n#{recent.map { |f| "• #{f[:content]}" }.join("\n")}" : ""}

      ## Your Task
      Return a JSON object with ALL text in #{lang_name}:

      {
        "summary": "2-3 paragraphs. Lead with the dominant pattern, cover key recurring issues and what leadership must act on. Cite specific upvote counts and quotes.",

        "sentiment": {
          "positive": "<X>%",
          "neutral": "<Y>%",
          "negative": "<Z>%"
        },

        "themes": [
          {
            "name": "Theme name",
            "count": <estimated number of feedbacks touching this theme>,
            "sentiment": "positive|neutral|negative",
            "examples": ["direct quote 1", "direct quote 2"],
            "upvote_weight": "high|medium|low"
          }
        ],

        "priority_issues": [
          "Specific issue with evidence — e.g. '7 feedbacks (3 upvoted) report the AC system breaking down repeatedly'"
        ],

        "recent_trend": "Is recent feedback different from overall? Note any emerging issues or improvements. Write 1-2 sentences or null if no notable trend.",

        "anonymous_pattern": "Any insight from the ratio of anonymous vs named submissions (psychological safety signal)? Write 1 sentence or null.",

        "recommendations": [
          "Specific, assignable action tied to the data"
        ],

        "action_items": [
          {
            "title": "Short action title (max 80 chars)",
            "description": "What to do, who should own it, why it matters — tied to specific feedback",
            "priority": "high|medium|low"
          }
        ]
      }

      Requirements:
      - Summary: 2-3 paragraphs max, concise
      - Themes: list 3-6 themes only, ranked by frequency + upvote signal
      - Priority issues: 3-5 specific, data-backed problems (1 sentence each)
      - Action items: 3-5 concrete tasks max
      - Be concise in all fields — do not pad or repeat information
      - Do not invent issues not present in the data
    PROMPT

    result_text = ClaudeService.sonnet_long.call(
      system_prompt: system_prompt,
      user_prompt:   user_prompt,
      max_tokens:    5000
    )

    result = parse_json_response(result_text)

    analysis = AiAnalysisResult.create!(
      workspace:      job.workspace,
      ai_job:         job,
      result_type:    "themes",
      resource_type:  "FeedbackBoard",
      resource_id:    board.id,
      output:         result,
      credits_cost:   3,
      response_count: feedbacks.count
    )

    # Create ActionItem records from AI output — skip near-duplicate titles
    if (items = result["action_items"]).present?
      existing_normalized = board.action_items.pluck(:title).map { |t| normalize_title(t) }
      created_this_run    = []

      items.each do |item|
        title = item["title"].to_s.truncate(200)
        norm  = normalize_title(title)
        next if similar_to_any?(norm, existing_normalized + created_this_run)

        priority = %w[high medium low].include?(item["priority"]) ? item["priority"] : "medium"
        ActionItem.create!(
          workspace:          job.workspace,
          feedback_board:     board,
          ai_analysis_result: analysis,
          title:              title,
          description:        item["description"],
          priority:           priority,
          status:             :pending
        )
        created_this_run << norm
      end
    end

    job.complete!(result)
  rescue => e
    if TRANSIENT_ERRORS.any? { |klass| e.is_a?(klass) }
      raise  # retry_on will handle retries and call job.fail! on discard
    else
      job.fail!(e.message)
    end
  end

  private

  def normalize_title(t)
    t.to_s.downcase.unicode_normalize(:nfkc).gsub(/[^\p{L}\p{N}\s]/u, "").gsub(/\s+/, " ").strip
  end

  # Returns true if `norm` is too similar to any title in `list`
  def similar_to_any?(norm, list)
    list.any? do |existing|
      next false if existing.empty? || norm.empty?
      # Exact match
      next true if existing == norm
      # One contains the other (handles prefix/suffix variations)
      next true if existing.include?(norm) || norm.include?(existing)
      # Word-overlap Jaccard ≥ 0.6
      w1 = norm.split; w2 = existing.split
      shared = (w1 & w2).length
      union  = (w1 | w2).length
      union > 0 && (shared.to_f / union) >= 0.6
    end
  end

  def parse_json_response(text)
    clean    = text.gsub(/\A\s*```(?:json)?\s*/i, '').gsub(/\s*```\s*\z/, '').strip
    json_str = clean.match(/\{.*\}/m)&.to_s || clean

    begin
      return JSON.parse(json_str)
    rescue JSON::ParserError
    end

    begin
      return JSON.parse(fix_json_strings(json_str))
    rescue JSON::ParserError
    end

    begin
      return JSON.parse(json_str.gsub(/[\x00-\x1F\x7F]/, ''))
    rescue JSON::ParserError => e
      raise "JSON parse failed: #{e.message.truncate(200)}"
    end
  end

  def fix_json_strings(s)
    out    = String.new(encoding: "UTF-8")
    in_str = false
    i      = 0
    while i < s.length
      c = s[i]
      if in_str
        case c
        when "\\"
          out << c << (s[i + 1] || "")
          i += 2
          next
        when '"'
          in_str = false
          out << c
        when "\n" then out << '\\n'
        when "\r" then out << '\\r'
        when "\t" then out << '\\t'
        else
          out << c
        end
      else
        out << c
        in_str = true if c == '"'
      end
      i += 1
    end
    out
  end
end
