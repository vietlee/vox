class AiPostVoteInsightJob < ApplicationJob
  queue_as :ai

  def perform(vote_id_or_job_id, is_job: false)
    if is_job
      job  = AiJob.find(vote_id_or_job_id)
      vote = Vote.find(job.resource_id)
    else
      vote = Vote.find(vote_id_or_job_id)
      job  = AiJob.create!(workspace: vote.workspace, job_type: "post_vote_insight", resource_type: "Vote", resource_id: vote.id, credits_cost: 2, status: :running, started_at: Time.current)
    end

    results = vote.results_by_option
    total   = vote.total_votes

    system_prompt = "You are an expert meeting facilitator. Generate instant, insightful comments about vote results in #{vote.workspace.language == 'vi' ? 'Vietnamese' : 'English'}."

    user_prompt = <<~PROMPT
      A live vote just ended. Provide 2-4 concise, insightful sentences about the results.

      Vote: #{vote.title}
      Type: #{vote.vote_type}
      Total votes: #{total}
      Results: #{results.to_json}

      Return JSON: { "insight": "2-4 sentences of insight", "highlight": "Most important finding" }
    PROMPT

    result_text = ClaudeService.for_feature("vote_insight").call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 512)
    result = JSON.parse(result_text.match(/\{.*\}/m)&.to_s || result_text)

    job.complete!(result)
    ActionCable.server.broadcast("vote_#{vote.id}", { type: "ai_insight", insight: result["insight"], highlight: result["highlight"] })
  rescue => e
    job&.fail!(e.message)
  end
end
