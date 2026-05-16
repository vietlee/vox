class AiSurveyBuilderJob < ApplicationJob
  queue_as :ai

  def perform(job_id)
    job = AiJob.find(job_id)
    job.start!

    prompt   = job.input_data["prompt"]
    language = job.input_data["language"] || "vi"

    system_prompt = <<~PROMPT
      You are an expert survey designer. Generate professional surveys in #{language == "vi" ? "Vietnamese" : "English"}.
      Always return valid JSON matching the schema exactly.
    PROMPT

    user_prompt = <<~PROMPT
      Create a comprehensive survey based on this objective: "#{prompt}"

      Return JSON with this exact structure:
      {
        "title": "Survey Title",
        "description": "Brief description",
        "questions": [
          {
            "title": "Question text",
            "question_type": "multiple_choice|checkbox|rating|short_text|long_text|nps|linear_scale",
            "required": true|false,
            "description": "optional help text",
            "options": ["Option 1", "Option 2"],
            "settings": {}
          }
        ]
      }

      Generate 8-12 diverse question types (NPS, rating, Likert, open-ended). Make questions clear and unbiased.
    PROMPT

    result_text = ClaudeService.sonnet.call(
      system_prompt: system_prompt,
      user_prompt: user_prompt,
      max_tokens: 4096
    )

    survey_data = JSON.parse(result_text.match(/\{.*\}/m)&.to_s || result_text)
    job.complete!(survey_data)
    job.workspace.active_subscription&.deduct_credits!(job.credits_cost)
  rescue => e
    job.fail!(e.message)
  end
end
