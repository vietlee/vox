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

    lang      = workspace.language == "en" ? "English" : "Vietnamese"
    system_prompt = <<~PROMPT
      You are VOX AI, a friendly and professional assistant for #{workspace.name}'s survey and feedback platform.
      You have access to their workspace data including surveys, votes, feedback, and members.
      Workspace context: #{context}

      Communication style:
      - Respond in #{lang}
      - Be concise and conversational — avoid overly long walls of text
      - Use short paragraphs, bullet points, or bold text when it helps clarity
      - Use markdown tables only for true comparative data with 3+ columns; prefer bullet lists otherwise
      - Use headings (##) sparingly — only for responses longer than 3 paragraphs
      - Lead with the most important insight, then provide supporting details
      - Use numbers and percentages when they add value
      - Be direct and confident; avoid filler phrases like "Great question!" or "Of course!"
    PROMPT

    messages = history.map { |h| { role: h["role"], content: h["content"] } }
    messages << { role: "user", content: message }

    result_text = ClaudeService.sonnet.call(
      system_prompt: system_prompt,
      messages: messages,
      max_tokens: 1024
    )

    job.complete!({ response: result_text })
  rescue => e
    job.fail!(e.message)
  end

  private

  def build_workspace_context(workspace)
    recent_surveys = workspace.surveys.order(created_at: :desc).limit(5).map do |s|
      "#{s.title} (#{s.response_count} responses, #{s.status})"
    end
    recent_votes = workspace.votes.order(created_at: :desc).limit(5).map do |v|
      "#{v.title} (#{v.status})"
    end
    recent_feedback = workspace.feedback_boards.order(created_at: :desc).limit(3).map do |f|
      "#{f.title} (#{f.feedbacks.count} items)"
    end
    {
      workspace_name:   workspace.name,
      surveys_total:    workspace.surveys.count,
      votes_total:      workspace.votes.count,
      members_total:    workspace.users.count,
      feedback_boards:  workspace.feedback_boards.count,
      recent_surveys:   recent_surveys,
      recent_votes:     recent_votes,
      recent_feedback:  recent_feedback
    }
  end
end
