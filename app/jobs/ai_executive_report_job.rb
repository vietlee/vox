require "net/http"

class AiExecutiveReportJob < ApplicationJob
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

    language     = job.input_data["language"] || "vi"
    lang_name    = language == "vi" ? "Vietnamese" : "English"
    user_context = job.input_data["user_context"].presence
    report_format= job.input_data["format"].presence || "pdf"

    # Pull the latest AI analysis as base context
    analysis  = survey.ai_analysis_results
                      .where(result_type: "executive_summary")
                      .order(created_at: :desc)
                      .first&.output || {}
    responses = survey.responses.completed

    # Extract pre-computed sentiment from analysis
    sentiment_data = analysis["sentiment"] || {}
    pos_from_analysis = sentiment_data["positive"].to_s.gsub('%', '').strip
    neg_from_analysis = sentiment_data["negative"].to_s.gsub('%', '').strip
    sentiment_hint = pos_from_analysis.present? ?
      "sentiment_positive: \"#{pos_from_analysis}%\", sentiment_negative: \"#{neg_from_analysis}%\"" :
      "sentiment_positive: \"derive from data\", sentiment_negative: \"derive from data\""

    context_block = user_context ? <<~CTX : ""
      ## Additional Focus from Report Requester
      The person requesting this report has provided the following context and focus areas:
      "#{user_context}"
      Make sure the report directly addresses these points.
    CTX

    system_prompt = <<~SYS.strip
      You are a senior analyst writing concise, board-ready executive reports.
      Reports go directly into leadership meetings — executives skim, they do NOT read long paragraphs.

      CRITICAL STYLE RULES:
      - Write ALL content in #{lang_name}
      - Be ruthlessly concise: each paragraph = 2-3 sentences max. No fluff, no padding.
      - Every sentence must contain a specific number, percentage, or finding. Never write vague generalities.
      - Recommendations must name WHO does WHAT by WHEN — not generic advice.
      - IMPORTANT: Return ONLY valid JSON. Use \\n\\n for paragraph breaks inside strings. No literal newlines inside JSON string values.
      - Do not include markdown, code fences, or any text outside the JSON object.
    SYS

    user_prompt = <<~PROMPT
      Create a professional executive report for the following survey.

      ## Survey Information
      Title: #{survey.title}
      #{survey.description.present? ? "Description: #{survey.description}" : ""}
      Report date: #{Date.current.strftime("%d/%m/%Y")}
      Total completed responses: #{responses.count}

      ## AI Analysis Data (use this as the factual foundation)
      #{analysis.to_json.truncate(4000)}

      #{context_block}

      ## Report Requirements
      Write a comprehensive executive report with the following JSON structure.
      ALL text values must be in #{lang_name}.

      {
        "title": "Professional report title in #{lang_name}",
        "subtitle": "Short subtitle in #{lang_name}, e.g. period or scope of the survey — #{Date.current.strftime("%m/%Y")}",
        "executive_summary": "EXACTLY 2 short paragraphs (each 2-3 sentences). Para 1: the single headline number/finding. Para 2: what it means and the top priority action. Use \\n\\n between paragraphs. NO filler sentences.",
        "key_metrics": {
          "response_count": #{responses.count},
          "sentiment_positive": "<USE EXACT VALUE FROM ANALYSIS: #{pos_from_analysis.presence || 'derive from data'}%>",
          "sentiment_negative": "<USE EXACT VALUE FROM ANALYSIS: #{neg_from_analysis.presence || 'derive from data'}%>",
          "top_concern": "The most critical issue in one sentence — be specific with data"
        },
        "sections": [
          {
            "heading": "Section title",
            "content": "2 paragraphs MAX. Each paragraph: 1-2 sentences with specific data. No padding.",
            "key_finding": "The single most important finding from this section, or null"
          }
        ],
        "recommendations": [
          {
            "priority": "high|medium|low",
            "action": "Specific, assignable action — who does what",
            "rationale": "Why this is important, tied to specific data",
            "expected_impact": "What improvement is expected"
          }
        ],
        "conclusion": "Closing paragraph summarizing the path forward and reinforcing urgency or optimism based on the data."
      }

      Hard constraints:
      - EXACTLY 3-4 sections (not 5). Each section: 2 short paragraphs max.
      - EXACTLY 3 recommendations (most impactful only).
      - conclusion: 1 sentence only.
      - Section headings and ALL text in #{lang_name}.
      - Sections = survey DATA only. Zero meta-commentary about the report itself.
      - #{user_context ? "Directly address: \"#{user_context}\" — weave into the sections, not as a separate section." : "Focus only on the most statistically significant findings."}
      - sentiment_positive/negative in key_metrics MUST be numeric percentages (e.g. "72%"), not "N/A" or placeholders.
    PROMPT

    result_text = ClaudeService.opus_long.call(
      system_prompt: system_prompt,
      user_prompt:   user_prompt,
      max_tokens:    8192
    )

    result = parse_json_response(result_text)

    # Attach real per-question chart data from DB
    result["chart_data"] = build_question_chart_data(survey)

    # Store metadata alongside the report content
    result["_meta"] = {
      "format"       => report_format,
      "language"     => language,
      "user_context" => user_context,
      "generated_at" => Time.current.iso8601
    }

    AiAnalysisResult.create!(
      workspace:      job.workspace,
      ai_job:         job,
      result_type:    "executive_report",
      resource_type:  "Survey",
      resource_id:    survey.id,
      output:         result,
      credits_cost:   15,
      response_count: responses.count
    )

    job.complete!(result)
  rescue => e
    if TRANSIENT_ERRORS.any? { |klass| e.is_a?(klass) }
      raise
    else
      job.fail!(e.message)
    end
  end

  private

  def build_question_chart_data(survey)
    completed_response_ids = survey.responses.completed.where(excluded: false).pluck(:id)
    return [] if completed_response_ids.empty?

    survey.questions.order(:position).filter_map do |q|
      base = Answer.where(question: q, response_id: completed_response_ids)

      case q.question_type.to_sym
      when :single_choice, :multiple_choice, :dropdown
        total = base.count
        next if total == 0
        # option_ids is jsonb — use @> with a JSON array literal
        options = q.question_options.order(:position).map do |opt|
          count = base.where("option_ids @> ?", [opt.id].to_json).count
          { "id" => opt.id, "label" => opt.label, "count" => count,
            "pct" => (count.to_f / total * 100).round(1) }
        end
        { "question_id" => q.id, "question" => q.title,
          "type" => q.question_type.to_s, "total" => total, "options" => options }

      when :rating, :nps, :linear_scale
        nums = base.where.not(numeric_value: nil).pluck(:numeric_value).map(&:to_i)
        next if nums.empty?
        max_val = q.nps? ? 10 : 5
        avg = (nums.sum.to_f / nums.size).round(1)
        dist = (1..max_val).map { |v| { "value" => v, "count" => nums.count(v) } }
        { "question_id" => q.id, "question" => q.title,
          "type" => q.question_type.to_s, "total" => nums.size,
          "avg" => avg, "max" => max_val, "distribution" => dist }

      when :short_text, :long_text
        count = base.where.not(text_value: [nil, ""]).count
        next if count == 0
        { "question_id" => q.id, "question" => q.title,
          "type" => q.question_type.to_s, "total" => count }
      end
    end.compact
  end

  def parse_json_response(text)
    clean    = text.gsub(/\A\s*```(?:json)?\s*/i, "").gsub(/\s*```\s*\z/, "").strip
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
      raise "Could not parse AI response as JSON: #{e.message.truncate(200)}"
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
