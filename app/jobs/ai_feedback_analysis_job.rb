class AiFeedbackAnalysisJob < ApplicationJob
  queue_as :ai

  def perform(job_id)
    job   = AiJob.find(job_id)
    board = FeedbackBoard.find(job.resource_id)
    job.start!

    feedbacks = board.feedbacks.approved.limit(200)
    return job.complete!({ error: "no_data" }) if feedbacks.empty?

    texts = feedbacks.pluck(:content)

    system_prompt = "You are an expert at analyzing employee feedback to extract actionable insights."

    user_prompt = <<~PROMPT
      Analyze #{feedbacks.count} pieces of employee feedback:

      #{texts.first(50).join("\n---\n")}

      Return JSON:
      {
        "summary": "Overall summary",
        "sentiment": { "positive": X%, "neutral": X%, "negative": X% },
        "themes": [{ "name": "", "count": 0, "sentiment": "positive|neutral|negative", "examples": [] }],
        "priority_issues": ["Issue 1", "Issue 2"],
        "recommendations": ["Action 1", "Action 2"]
      }
    PROMPT

    result_text = ClaudeService.sonnet.call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 3000)
    result = JSON.parse(result_text.match(/\{.*\}/m)&.to_s || result_text)

    AiAnalysisResult.create!(workspace: job.workspace, ai_job: job, result_type: "themes", resource_type: "FeedbackBoard", resource_id: board.id, output: result, credits_cost: 3, response_count: feedbacks.count)
    job.complete!(result)
    job.workspace.active_subscription&.deduct_credits!(3)
  rescue => e
    job.fail!(e.message)
  end
end
