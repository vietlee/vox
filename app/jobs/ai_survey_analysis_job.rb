require "net/http"

class AiSurveyAnalysisJob < ApplicationJob
  queue_as :ai

  TRANSIENT_ERRORS = [Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT].freeze

  retry_on(*TRANSIENT_ERRORS, wait: 20.seconds, attempts: 2) do |job_instance, error|
    ai_job = AiJob.find_by(id: job_instance.arguments.first)
    ai_job&.fail!("Network timeout after retries: #{error.message.truncate(200)}")
  end

  def perform(job_id)
    job    = AiJob.find(job_id)
    survey = Survey.find(job.resource_id)
    job.start!

    responses = survey.responses.completed.includes(answers: :question)
    return job.complete!({ error: "no_data" }) if responses.empty?

    language  = job.input_data&.dig("language") || survey.workspace.language || "vi"
    lang_name = language == "vi" ? "Vietnamese" : "English"

    data_summary = build_rich_summary(survey, responses)
    # Truncate JSON payload to stay well within token limits
    data_json = data_summary.to_json
    data_json = data_json.truncate(10_000) if data_json.length > 10_000

    system_prompt = <<~SYSTEM
      You are a senior HR analyst and organizational consultant specializing in employee experience.
      You transform raw survey data into executive-ready insights that drive real organizational change.

      Your analysis must:
      - Be written entirely in #{lang_name}
      - Be direct, specific, and actionable — avoid vague statements like "improve communication"
      - Reference actual data (percentages, scores, specific quotes) to support every claim
      - Prioritize the most impactful findings, not just the most common ones
      - Frame recommendations in terms of business/people impact, not just survey scores

      CRITICAL JSON RULES — you MUST follow these exactly:
      - Return ONLY a valid JSON object. No text before or after it.
      - Do NOT wrap in markdown code fences.
      - Inside JSON string values, use \\n for line breaks — NEVER use actual newline characters.
      - All string values must be on a single line within the JSON structure.
    SYSTEM

    user_prompt = <<~PROMPT
      Analyze the following survey results and provide deep, actionable insights.

      ## Survey Context
      Title: #{survey.title}
      Total completed responses: #{responses.count}
      #{survey.description.present? ? "Description: #{survey.description}" : ""}

      ## Question-by-Question Data
      #{data_json}

      ## Instructions
      Provide a JSON response with this exact structure. Write ALL text values in #{lang_name}.

      {
        "executive_summary": "3-4 paragraphs. Start with the single most important finding. Then cover overall sentiment, key patterns across questions, and what this data means for the organization. Be specific — cite scores and percentages.",

        "key_metrics": {
          "average_score": <overall average for scale questions, null if none>,
          "response_rate_quality": "brief note on data reliability",
          "standout_high": "question with best result and its score",
          "standout_low": "question with worst result and its score"
        },

        "sentiment": {
          "positive": "<X>%",
          "neutral": "<Y>%",
          "negative": "<Z>%",
          "sentiment_note": "one sentence explaining the sentiment pattern"
        },

        "question_insights": [
          {
            "question": "question title",
            "finding": "key finding for this specific question with data",
            "concern_level": "high|medium|low"
          }
        ],

        "top_themes": [
          {
            "theme": "theme name",
            "count": <number of responses mentioning this>,
            "percentage": <percentage of total responses>,
            "sentiment": "positive|neutral|negative"
          }
        ],

        "anomalies": [
          "Specific outlier or unexpected pattern with data to back it up"
        ],

        "highlights": [
          "Specific positive finding with data — e.g. '85% rated X as excellent'"
        ],

        "recommendations": [
          {
            "action": "Specific, concrete action — who does what by when",
            "rationale": "Why this matters, tied to specific data from the survey",
            "impact": "Expected outcome if this is done",
            "priority": "high|medium|low"
          }
        ]
      }

      Requirements:
      - Generate 3-6 recommendations, ordered by priority
      - Each recommendation must reference specific data from the survey
      - Highlights should only include genuinely positive findings
      - Anomalies should be truly noteworthy, not just random variation
      - question_insights: include one entry per question that has meaningful data
    PROMPT

    result_text = ClaudeService.sonnet_long.call(
      system_prompt: system_prompt,
      user_prompt:   user_prompt,
      max_tokens:    8000
    )

    result = parse_json_response(result_text)

    AiAnalysisResult.create!(
      workspace:      job.workspace,
      ai_job:         job,
      result_type:    "executive_summary",
      resource_type:  "Survey",
      resource_id:    survey.id,
      output:         result,
      credits_cost:   job.credits_cost,
      response_count: responses.count
    )

    job.complete!(result)
  rescue => e
    if TRANSIENT_ERRORS.any? { |klass| e.is_a?(klass) }
      raise  # retry_on will handle retries and call job.fail! on discard
    else
      job.fail!(e.message)
    end
  end

  private

  def parse_json_response(text)
    clean    = text.gsub(/\A\s*```(?:json)?\s*/i, '').gsub(/\s*```\s*\z/, '').strip
    json_str = clean.match(/\{.*\}/m)&.to_s || clean

    # Try 1: direct parse
    begin
      return JSON.parse(json_str)
    rescue JSON::ParserError
    end

    # Try 2: escape literal control characters inside JSON strings
    begin
      return JSON.parse(fix_json_strings(json_str))
    rescue JSON::ParserError
    end

    # Try 3: strip all ASCII control chars and retry
    begin
      return JSON.parse(json_str.gsub(/[\x00-\x1F\x7F]/, ''))
    rescue JSON::ParserError
    end

    # Try 4: attempt to repair truncated JSON by closing open structures
    begin
      return JSON.parse(repair_truncated_json(json_str))
    rescue JSON::ParserError => e
      raise "JSON parse failed: #{e.message.truncate(200)}"
    end
  end

  # Close any unclosed arrays/objects in a truncated JSON string
  def repair_truncated_json(s)
    # Remove trailing incomplete key-value pair or comma
    repaired = s.gsub(/,\s*\z/, '').gsub(/,\s*"[^"]*"\s*:\s*[^,}\]]*\z/, '')
    # Count unclosed brackets
    depth_obj = 0; depth_arr = 0; in_str = false; i = 0
    while i < repaired.length
      c = repaired[i]
      if in_str
        in_str = false if c == '"' && repaired[i-1] != '\\'
      else
        case c
        when '"' then in_str = true
        when '{' then depth_obj += 1
        when '}' then depth_obj -= 1
        when '[' then depth_arr += 1
        when ']' then depth_arr -= 1
        end
      end
      i += 1
    end
    # Close unclosed structures
    repaired + (']' * [depth_arr, 0].max) + ('}' * [depth_obj, 0].max)
  end

  # Walk the JSON character-by-character and escape literal control chars inside strings
  def fix_json_strings(s)
    out    = String.new(encoding: "UTF-8")
    in_str = false
    i      = 0
    while i < s.length
      c = s[i]
      if in_str
        case c
        when "\\"
          # Escaped character — copy both the backslash and next char verbatim
          out << c << (s[i + 1] || "")
          i += 2
          next
        when '"'
          in_str = false
          out << c
        when "\n"
          out << '\\n'
        when "\r"
          out << '\\r'
        when "\t"
          out << '\\t'
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

  def build_rich_summary(survey, responses)
    survey.questions.order(:position).includes(:question_options).map do |q|
      answers = responses.flat_map { |r| r.answers.select { |a| a.question_id == q.id } }
      next nil if answers.empty?

      entry = {
        question:  q.title,
        type:      q.question_type,
        required:  q.required?,
        answered:  answers.count
      }

      case q.question_type
      when "linear_scale", "nps", "rating"
        numeric_vals = answers.map(&:numeric_value).compact.map(&:to_f)
        if numeric_vals.any?
          sorted = numeric_vals.sort
          entry[:mean]     = (numeric_vals.sum / numeric_vals.size).round(2)
          entry[:median]   = sorted[sorted.size / 2]
          entry[:min]      = sorted.first
          entry[:max]      = sorted.last
          entry[:distribution] = numeric_vals.group_by { |v| v.round }.transform_values(&:count)
        end

      when "single_choice", "multiple_choice", "dropdown"
        option_labels = q.question_options.index_by(&:id)
        counts = Hash.new(0)
        answers.each do |a|
          (a.option_ids || []).each { |oid| counts[oid] += 1 }
        end
        entry[:options] = counts.map do |oid, cnt|
          label = option_labels[oid]&.label || oid.to_s
          { label: label, count: cnt, percentage: (cnt.to_f / responses.count * 100).round(1) }
        end.sort_by { |o| -o[:count] }

      when "short_text", "long_text"
        texts = answers.map(&:text_value).compact.reject(&:blank?)
        entry[:response_count] = texts.count
        safe_texts = texts.first(15).map { |t| t.gsub('"', "'").gsub(/[\x00-\x1F]/, ' ').strip.truncate(300) }
        entry[:responses] = safe_texts

      when "date_time"
        dates = answers.map(&:date_value).compact
        entry[:response_count] = dates.count

      when "file_upload"
        entry[:upload_count] = answers.count { |a| a.uploaded_file.attached? }
      end

      entry
    end.compact
  end
end
