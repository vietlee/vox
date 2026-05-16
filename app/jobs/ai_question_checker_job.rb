class AiQuestionCheckerJob < ApplicationJob
  queue_as :ai

  def perform(job_id)
    job = AiJob.find(job_id)
    job.start!

    question_text = job.input_data["question_text"]
    language      = job.input_data["language"] || "vi"

    system_prompt = "You are a survey methodology expert. Analyze survey questions for quality issues."

    user_prompt = <<~PROMPT
      Analyze this survey question for quality issues: "#{question_text}"

      Check for:
      1. Leading questions (biased phrasing)
      2. Double-barreled questions (multiple questions in one)
      3. Ambiguous language
      4. Loaded language

      Return JSON:
      {
        "issues": ["issue1", "issue2"],
        "severity": "none|warning|error",
        "suggestion": "Improved version if needed",
        "explanation": "Brief explanation"
      }
    PROMPT

    result_text = ClaudeService.haiku.call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 512)
    result = JSON.parse(result_text.match(/\{.*\}/m)&.to_s || result_text)
    job.complete!(result)
  rescue => e
    job.fail!(e.message)
  end
end
