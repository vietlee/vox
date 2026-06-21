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

    # ─── LAYER 1: Pre-compute deterministic stats ───────────────────────
    total_upvoted    = feedback_data.count { |f| f[:upvotes] > 0 }
    total_upvote_pts = feedback_data.sum { |f| f[:upvotes] }
    anon_count       = feedback_data.count { |f| f[:anonymous] }
    recent_count     = feedback_data.count { |f| f[:days_ago] <= 14 }
    avg_upvotes      = analyzed_count > 0 ? (total_upvote_pts.to_f / analyzed_count).round(1) : 0

    computed_stats = {
      total_feedbacks:    total_count,
      analyzed:           analyzed_count,
      with_upvotes:       total_upvoted,
      total_upvote_pts:   total_upvote_pts,
      avg_upvotes_per_fb: avg_upvotes,
      anonymous_count:    anon_count,
      anonymous_pct:      analyzed_count > 0 ? (anon_count.to_f / analyzed_count * 100).round(1) : 0,
      recent_14d_count:   recent_count,
      recent_14d_pct:     analyzed_count > 0 ? (recent_count.to_f / analyzed_count * 100).round(1) : 0
    }

    system_prompt = <<~SYSTEM
      You are a senior HR consultant analyzing employee feedback for leadership action.
      Write entirely in #{lang_name}. Be specific and direct.

      CRITICAL RULES:
      1. Do NOT invent counts or percentages. The only reliable counts are in "computed_stats".
      2. For themes: identify theme names and cite direct quotes — do NOT assign fabricated counts.
      3. Upvoted feedback = community-validated — weight it higher.
      4. Every recommendation must be assignable (who does what).
      5. Return ONLY valid JSON. No markdown fences.
    SYSTEM

    user_prompt = <<~PROMPT
      Analyze feedback for: "#{board.title}"
      #{board.description.present? ? "Description: #{board.description}" : ""}

      ## Pre-computed Stats (use these exact numbers — do not estimate)
      #{computed_stats.to_json}

      ## All Feedback (numbered, sorted by upvotes then recency)
      #{feedback_data.map.with_index(1) { |f, i|
        upvote_label = f[:upvotes] > 0 ? " [#{f[:upvotes]} upvotes]" : ""
        recency_label = f[:days_ago] <= 7 ? " [this week]" : f[:days_ago] <= 14 ? " [2 weeks]" : ""
        "#{i}. #{f[:content]}#{upvote_label}#{recency_label}"
      }.join("\n")}

      #{top_upvoted.any? ? "\n## Most Upvoted\n" + top_upvoted.map { |f| "• [#{f[:upvotes]} votes] #{f[:content]}" }.join("\n") : ""}
      #{recent.any? && recent.count < analyzed_count ? "\n## Recent (last 14 days)\n" + recent.map { |f| "• #{f[:content]}" }.join("\n") : ""}

      Return JSON with ALL text in #{lang_name}:
      {
        "summary": "2-3 paragraphs. Lead with most impactful finding. Cite upvote counts and direct quotes. Use \\n\\n between paragraphs.",

        "sentiment": {
          "positive": "<X>%",
          "neutral": "<Y>%",
          "negative": "<Z>%",
          "note": "1 sentence on the overall tone — reference specific upvote-backed feedback"
        },

        "themes": [
          {
            "name": "Theme name",
            "sentiment": "positive|neutral|negative",
            "upvote_weight": "high|medium|low",
            "representative_quotes": ["exact quote from the data", "another exact quote"]
          }
        ],

        "priority_issues": [
          "Specific issue with evidence — reference upvote count or feedback number if applicable"
        ],

        "recent_trend": "Is recent feedback (last 14 days) different from overall? 1-2 sentences or null.",

        "anonymous_pattern": "What does the #{computed_stats[:anonymous_pct]}% anonymous rate suggest about psychological safety? 1 sentence.",

        "recommendations": ["Specific, assignable action"],

        "action_items": [
          {
            "title": "Short title (max 80 chars)",
            "description": "What to do, who owns it, why it matters — cite specific feedback",
            "priority": "high|medium|low"
          }
        ]
      }

      Rules:
      - themes: 3-6 only, ranked by upvote signal + frequency. Quotes must be verbatim from the data.
      - priority_issues: 3-5 specific problems (1 sentence each)
      - action_items: 3-5 max
      - sentiment %: estimate based on overall tone of feedbacks (positive/constructive/critical)
    PROMPT

    result_text = ClaudeService.for_feature("feedback_analysis", timeout: 240).call(
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
