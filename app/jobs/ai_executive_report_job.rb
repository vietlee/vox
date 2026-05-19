class AiExecutiveReportJob < ApplicationJob
  queue_as :ai

  def perform(job_id)
    job    = AiJob.find(job_id)
    survey = Survey.find(job.resource_id)
    job.start!

    language  = job.input_data["language"] || "vi"
    lang_name = language == "vi" ? "Vietnamese" : "English"

    analysis  = survey.ai_analysis_results.order(created_at: :desc).first&.output || {}
    responses = survey.responses.completed

    system_prompt = <<~SYS.strip
      You are a senior HR consultant writing professional executive reports.
      Write ALL text content in #{lang_name}.
      IMPORTANT: Return ONLY valid JSON. Do not use newlines inside JSON string values — use \\n instead.
      Do not include markdown, code fences, or any text outside the JSON object.
    SYS

    user_prompt = <<~PROMPT
      Write an executive report for this survey.

      Survey title: #{survey.title}
      Date: #{Date.current}
      Total completed responses: #{responses.count}
      AI analysis data: #{analysis.to_json.truncate(3000)}

      Return a JSON object with exactly this structure:
      {
        "title": "string",
        "executive_summary": "string (2-3 paragraphs, use \\n\\n between paragraphs)",
        "sections": [
          {
            "heading": "string",
            "content": "string",
            "key_finding": "string or null"
          }
        ],
        "recommendations": [
          {
            "priority": "high|medium|low",
            "action": "string",
            "expected_impact": "string"
          }
        ],
        "conclusion": "string"
      }

      Include 3-5 sections and 3-5 recommendations. Keep all string values on a single line (no literal newlines inside strings).
    PROMPT

    result_text = ClaudeService.sonnet_long.call(
      system_prompt: system_prompt,
      user_prompt: user_prompt,
      max_tokens: 6000
    )

    result = parse_json_response(result_text)

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
    job.fail!(e.message)
  end

  private

  def parse_json_response(text)
    # Strip markdown code fences
    clean = text.gsub(/\A\s*```(?:json)?\s*/i, "").gsub(/\s*```\s*\z/, "").strip

    # Try direct parse first
    begin
      return JSON.parse(clean)
    rescue JSON::ParserError
    end

    # Extract the outermost {...} block
    match = clean.match(/\{.*\}/m)&.to_s
    return JSON.parse(match) if match

    raise "Could not parse AI response as JSON"
  end
end
