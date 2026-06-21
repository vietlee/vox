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
      You are VOX AI, a data-aware assistant for #{workspace.name}'s workspace on VOX platform.
      You have full access to their real workspace data below — surveys, votes, feedback boards, quiz sets, and dynamic forms.
      Use this data to give specific, data-backed answers with actual numbers and content from the context.
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

    result_text = ClaudeService.for_feature("ai_chat").call(
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
    lines << "Members: #{workspace.users.count} | Surveys: #{workspace.surveys.count} | Votes: #{workspace.votes.count} | Feedback boards: #{workspace.feedback_boards.count} | Quiz sets: #{workspace.quiz_sets.count} | Dynamic forms: #{workspace.dynamic_forms.count}"
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

    # ── Quiz sets with results ───────────────────────────────────────────────
    quiz_sets = workspace.quiz_sets.order(updated_at: :desc).limit(6)
    if quiz_sets.any?
      lines << "## QUIZ SETS"
      quiz_sets.each do |qs|
        attempts = qs.quiz_attempts.where.not(submitted_at: nil)
        avg = attempts.any? ? (attempts.sum(&:score_pct).to_f / attempts.count).round(1) : nil
        passed = attempts.select(&:passed?).count
        pass_rate = attempts.any? ? (passed * 100.0 / attempts.count).round(1) : nil
        lines << "### #{qs.title} [#{qs.status}, #{qs.quiz_questions.count} questions, #{attempts.count} attempts]"
        lines << "  Avg score: #{avg ? "#{avg}%" : "N/A"} | Pass rate: #{pass_rate ? "#{pass_rate}%" : "N/A"} | Passing threshold: #{qs.passing_score}%"
        if attempts.any?
          # Most missed questions
          q_stats = qs.quiz_questions.map do |q|
            correct = attempts.count { |a| a.quiz_attempt_answers.any? { |ans| ans.quiz_question_id == q.id && ans.is_correct? } }
            rate = (correct * 100.0 / attempts.count).round
            { text: q.question_text.truncate(80), rate: rate }
          end.sort_by { |s| s[:rate] }
          weakest = q_stats.first(3)
          if weakest.any?
            lines << "  Weakest questions:"
            weakest.each { |s| lines << "    - #{s[:text]} (#{s[:rate]}% correct)" }
          end
        end
        lines << ""
      end
    end

    # ── Dynamic Forms with recent submissions ────────────────────────────────
    forms = workspace.dynamic_forms.order(updated_at: :desc).limit(5)
    if forms.any?
      lines << "## DYNAMIC FORMS"
      forms.each do |f|
        sub_count = f.dynamic_form_submissions.count
        lines << "### #{f.title} [#{f.status}, #{sub_count} submissions]"
        pending = f.dynamic_form_submissions.where(status: "pending").count
        lines << "  Pending review: #{pending}" if pending > 0
        lines << ""
      end
    end

    lines.join("\n")
  end
end
