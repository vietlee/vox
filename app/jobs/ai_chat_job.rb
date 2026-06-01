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
      You are VOX AI, a data-aware assistant for #{workspace.name}'s survey and feedback platform.
      You have full access to their real workspace data below — use it to give specific, data-backed answers.
      When asked about surveys, votes, or feedback, reference actual numbers and content from the context.
      If something is not in the context, say so clearly — do not make up data.

      === WORKSPACE DATA ===
      #{context}
      === END DATA ===

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
    lines = []
    lines << "Workspace: #{workspace.name}"
    lines << "Members: #{workspace.users.count} | Surveys: #{workspace.surveys.count} | Votes: #{workspace.votes.count} | Feedback boards: #{workspace.feedback_boards.count}"
    lines << ""

    # ── Surveys with AI analysis ─────────────────────────────────────────────
    surveys = workspace.surveys.order(updated_at: :desc).limit(6)
    if surveys.any?
      lines << "## SURVEYS"
      surveys.each do |s|
        lines << "### #{s.title} [#{s.status}, #{s.response_count} responses]"

        analysis = s.ai_analysis_results
                    .where(result_type: "executive_summary")
                    .order(created_at: :desc)
                    .first&.output
        if analysis
          sent = analysis["sentiment"]
          if sent.is_a?(Hash)
            lines << "Sentiment: positive #{sent['positive']}, negative #{sent['negative']}, neutral #{sent['neutral']}"
          end
          themes = (analysis["top_themes"] || analysis["themes"] || []).first(5)
          if themes.any?
            lines << "Top themes: " + themes.map { |t| "#{t['theme'] || t['name']} #{t['percentage']}%" }.join(", ")
          end
          if (summary = analysis["summary"].presence)
            lines << "Summary: #{summary.truncate(300)}"
          end
          findings = analysis["key_findings"] || []
          if findings.any?
            lines << "Key findings: " + findings.first(3).map { |f| f.is_a?(Hash) ? f.values.first : f.to_s }.join(" | ")
          end
        else
          lines << "(No AI analysis yet)"
        end
        lines << ""
      end
    end

    # ── Votes with results ───────────────────────────────────────────────────
    votes = workspace.votes.order(updated_at: :desc).limit(6)
    if votes.any?
      lines << "## VOTES"
      votes.each do |v|
        total = v.vote_options.sum(:votes_count)
        lines << "### #{v.title} [#{v.status}, #{v.vote_type}, #{v.vote_responses.count} participants]"
        if v.vote_options.any?
          v.vote_options.order(:position).each do |opt|
            pct = total > 0 ? (opt.votes_count.to_f / total * 100).round(1) : 0
            lines << "  - #{opt.label}: #{opt.votes_count} votes (#{pct}%)"
          end
        end
        lines << ""
      end
    end

    # ── Feedback boards with top items ───────────────────────────────────────
    boards = workspace.feedback_boards.order(updated_at: :desc).limit(5)
    if boards.any?
      lines << "## FEEDBACK BOARDS"
      boards.each do |board|
        approved = board.feedbacks.approved
        lines << "### #{board.title} [#{board.feedbacks.count} total, #{approved.count} approved]"

        top_items = approved
          .includes(:feedback_upvotes)
          .sort_by { |f| -f.feedback_upvotes.size }
          .first(10)

        if top_items.any?
          top_items.each do |f|
            upvotes = f.feedback_upvotes.size
            lines << "  [#{upvotes} upvotes | #{f.admin_status}] #{f.content.squish.truncate(120)}"
          end
        else
          lines << "  (No approved feedback yet)"
        end
        lines << ""
      end
    end

    lines.join("\n")
  end
end
