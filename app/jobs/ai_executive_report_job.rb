class AiExecutiveReportJob < ApplicationJob
  queue_as :ai

  def perform(job_id)
    job    = AiJob.find(job_id)
    survey = Survey.find(job.resource_id)
    job.start!

    language  = job.input_data["language"] || "vi"
    lang_name = language == "vi" ? "Vietnamese" : "English"

    analysis = survey.ai_analysis_results.order(created_at: :desc).first&.output || {}
    responses = survey.responses.completed

    system_prompt = "You are a senior HR consultant writing executive reports. Write in #{lang_name}, professional tone."

    user_prompt = <<~PROMPT
      Write an executive report for this employee survey.

      Survey: #{survey.title}
      Date: #{Date.current}
      Responses: #{responses.count}
      Analysis: #{analysis.to_json}

      Return JSON:
      {
        "title": "Report title",
        "executive_summary": "1 page summary",
        "sections": [
          { "heading": "Section title", "content": "Section content", "key_finding": "Main finding" }
        ],
        "recommendations": [{ "priority": 1, "action": "", "expected_impact": "" }],
        "conclusion": "Closing paragraph"
      }
    PROMPT

    result_text = ClaudeService.sonnet.call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 6000)
    result = JSON.parse(result_text.match(/\{.*\}/m)&.to_s || result_text)

    AiAnalysisResult.create!(workspace: job.workspace, ai_job: job, result_type: "executive_report", resource_type: "Survey", resource_id: survey.id, output: result, credits_cost: 15, response_count: responses.count)
    job.complete!(result)
    job.workspace.active_subscription&.deduct_credits!(15)
  rescue => e
    job.fail!(e.message)
  end
end
