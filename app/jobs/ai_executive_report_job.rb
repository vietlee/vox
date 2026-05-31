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

    context_block = user_context ? <<~CTX : ""
      ## Additional Focus from Report Requester
      The person requesting this report has provided the following context and focus areas:
      "#{user_context}"
      Make sure the report directly addresses these points.
    CTX

    system_prompt = <<~SYS.strip
      You are a senior HR consultant and organizational strategist writing board-ready executive reports.
      Your reports are used directly in leadership meetings — they must be polished, data-driven, and immediately actionable.

      Rules:
      - Write ALL content in #{lang_name}
      - Every claim must reference actual data from the survey
      - Recommendations must be specific and assignable (not generic)
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
        "title": "Professional report title",
        "subtitle": "e.g. 'Internal HR Survey — #{Date.current.strftime("%B %Y")}'",
        "executive_summary": "3-4 paragraphs covering: overall picture, key findings, sentiment, and what leadership should know. Cite specific numbers. Use \\n\\n between paragraphs.",
        "key_metrics": {
          "response_count": #{responses.count},
          "sentiment_positive": "X%",
          "sentiment_negative": "X%",
          "top_concern": "The most critical issue in one sentence"
        },
        "sections": [
          {
            "heading": "Section title",
            "content": "Detailed analysis with data. Use \\n\\n for paragraph breaks.",
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

      Requirements:
      - 3-5 sections covering distinct survey findings themes (e.g. Work Environment, Management, Facilities, Satisfaction Scores)
      - 3-5 recommendations ordered by priority (high first)
      - Each section content: 2-3 paragraphs max, concise and data-backed
      - executive_summary: 2-3 paragraphs max
      - sections and recommendations must directly connect to the AI analysis data provided
      - #{user_context ? "Address the requester's focus areas throughout the content and recommendations — but do NOT create a section about how to read the report or describe file formats." : "Focus on the most impactful findings"}
      - CRITICAL: sections must be about survey DATA and FINDINGS only. Never write a section about the report format, file type, how to read charts, or instructions for the reader. Those belong in the conclusion at most, in one sentence.
      - Be concise — quality over length. Do not pad content.
    PROMPT

    result_text = ClaudeService.sonnet_long.call(
      system_prompt: system_prompt,
      user_prompt:   user_prompt,
      max_tokens:    8192
    )

    result = parse_json_response(result_text)

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
