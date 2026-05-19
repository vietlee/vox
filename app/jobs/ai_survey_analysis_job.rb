class AiSurveyAnalysisJob < ApplicationJob
  queue_as :ai

  def perform(job_id)
    job    = AiJob.find(job_id)
    survey = Survey.find(job.resource_id)
    job.start!

    responses = survey.responses.completed.includes(:answers, answers: :question)
    return job.complete!({ error: "no_data" }) if responses.empty?

    # Build summary data for Claude
    data_summary = build_summary(survey, responses)

    language  = job.input_data&.dig("language") || survey.workspace.language || "vi"
    lang_name = language == "vi" ? "Vietnamese" : "English"
    system_prompt = "You are a data analyst expert in employee surveys. Provide actionable insights in #{lang_name}."

    user_prompt = <<~PROMPT
      Analyze this survey data and provide comprehensive insights:

      Survey: #{survey.title}
      Total responses: #{responses.count}
      Data: #{data_summary.to_json}

      Provide JSON with:
      {
        "executive_summary": "2-3 paragraph overview",
        "key_metrics": { "average_score": X, "completion_rate": X },
        "sentiment": { "positive": X, "neutral": X, "negative": X },
        "top_themes": [{ "theme": "", "count": 0, "percentage": 0, "samples": [] }],
        "anomalies": ["Notable outliers or patterns"],
        "recommendations": [{ "action": "", "rationale": "", "priority": "high|medium|low" }],
        "highlights": ["Key findings"]
      }
    PROMPT

    result_text = ClaudeService.sonnet.call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 4096)
    clean = result_text.gsub(/\A```(?:json)?\s*/i, '').gsub(/\s*```\z/, '').strip
    result = JSON.parse(clean.match(/\{.*\}/m)&.to_s || clean)

    AiAnalysisResult.create!(
      workspace: job.workspace,
      ai_job: job,
      result_type: "executive_summary",
      resource_type: "Survey",
      resource_id: survey.id,
      output: result,
      credits_cost: job.credits_cost,
      response_count: responses.count
    )

    job.complete!(result)
  rescue => e
    job.fail!(e.message)
  end

  private

  def build_summary(survey, responses)
    survey.questions.map do |q|
      answers = responses.flat_map { |r| r.answers.select { |a| a.question_id == q.id } }
      { question: q.title, type: q.question_type, answer_count: answers.count,
        sample_answers: answers.first(20).map(&:text_value).compact }
    end
  end
end
