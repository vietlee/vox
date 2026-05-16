class AiChatJob < ApplicationJob
  queue_as :ai

  def perform(job_id)
    job = AiJob.find(job_id)
    job.start!

    message   = job.input_data["message"]
    history   = job.input_data["conversation_history"] || []
    workspace = job.workspace

    # Build workspace context
    context = build_workspace_context(workspace)

    system_prompt = <<~PROMPT
      You are an AI assistant for #{workspace.name}'s HR analytics platform.
      You have access to their survey, vote, and feedback data.
      Answer questions clearly and concisely. Include numbers when relevant.
      Context: #{context}
    PROMPT

    messages = history.map { |h| { role: h["role"], content: h["content"] } }
    messages << { role: "user", content: message }

    result_text = ClaudeService.sonnet.call(
      system_prompt: system_prompt,
      user_prompt: message,
      max_tokens: 1024
    )

    job.complete!({ response: result_text })
    workspace.active_subscription&.deduct_credits!(2)
  rescue => e
    job.fail!(e.message)
  end

  private

  def build_workspace_context(workspace)
    {
      surveys_count:   workspace.surveys.count,
      votes_count:     workspace.votes.count,
      members_count:   workspace.users.count,
      recent_surveys:  workspace.surveys.order(created_at: :desc).limit(5).pluck(:title, :response_count)
    }
  end
end
