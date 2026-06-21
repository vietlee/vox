class AiModerationJob < ApplicationJob
  queue_as :ai

  def perform(feedback_id)
    feedback = Feedback.find(feedback_id)

    system_prompt = "You are a content moderator for a corporate feedback platform. Be conservative — flag borderline content."

    user_prompt = <<~PROMPT
      Moderate this employee feedback:
      "#{feedback.content}"

      Return JSON:
      {
        "decision": "safe|flagged|rejected",
        "reason": "Brief reason if flagged/rejected",
        "priority_score": 0.0-1.0,
        "topics": ["topic1", "topic2"]
      }

      Reject: explicit harassment, spam, completely off-topic
      Flag: personal attacks, very sensitive claims, ambiguous content
      Safe: constructive feedback, opinions, suggestions
    PROMPT

    result_text = ClaudeService.for_feature("moderation").call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 256)
    result = JSON.parse(result_text.match(/\{.*\}/m)&.to_s || result_text)

    moderation_status = case result["decision"]
    when "safe"     then :safe
    when "flagged"  then :flagged
    when "rejected" then :auto_rejected
    else :safe
    end

    new_status = case result["decision"]
    when "safe"     then feedback.feedback_board.manual_approval? ? :pending : :approved
    when "rejected" then :rejected
    else :pending
    end

    feedback.update!(
      moderation_status: moderation_status,
      status: new_status,
      priority_score: result["priority_score"],
      cluster_label: result["topics"]&.first,
      moderation_reason: result["reason"],
      ai_analysis: result
    )

    feedback.workspace.active_subscription&.deduct_credits!(1)
  rescue => e
    Rails.logger.error "AI Moderation failed for feedback #{feedback_id}: #{e.message}"
  end
end
