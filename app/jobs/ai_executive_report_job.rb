require "net/http"

class AiExecutiveReportJob < ApplicationJob
  queue_as :ai

  TRANSIENT_ERRORS = [Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT].freeze

  retry_on(*TRANSIENT_ERRORS, wait: 20.seconds, attempts: 2) do |job_instance, error|
    ai_job = AiJob.find_by(id: job_instance.arguments.first)
    ai_job&.fail!("Network timeout after retries: #{error.message.truncate(200)}")
  end

  def perform(job_id)
    job    = AiJob.find(job_id)
    survey = Survey.find(job.resource_id)
    job.start!

    language     = job.input_data["language"] || "vi"
    lang_name    = language == "vi" ? "Vietnamese" : "English"
    user_context = job.input_data["user_context"].presence
    report_format= job.input_data["format"].presence || "pdf"

    # Pull the latest AI analysis as base context
    analysis  = survey.ai_analysis_results
                      .where(result_type: "executive_summary")
                      .order(created_at: :desc)
                      .first&.output || {}
    responses = survey.responses.completed

    # Extract pre-computed sentiment from analysis
    sentiment_data = analysis["sentiment"] || {}
    pos_from_analysis = sentiment_data["positive"].to_s.gsub('%', '').strip
    neg_from_analysis = sentiment_data["negative"].to_s.gsub('%', '').strip
    sentiment_hint = pos_from_analysis.present? ?
      "sentiment_positive: \"#{pos_from_analysis}%\", sentiment_negative: \"#{neg_from_analysis}%\"" :
      "sentiment_positive: \"derive from data\", sentiment_negative: \"derive from data\""

    context_block = user_context ? <<~CTX : ""
      ## Additional Focus from Report Requester
      The person requesting this report has provided the following context and focus areas:
      "#{user_context}"
      Make sure the report directly addresses these points.
    CTX

    # Build question reference list with position numbers
    questions_list = survey.questions.order(:position)
    questions_ref  = questions_list.each_with_index.map { |q, i|
      "  Q#{i+1} (ID #{q.id}) [#{q.question_type}] #{q.title}"
    }.join("\n")

    system_prompt = <<~SYS.strip
      You are an expert survey analyst. Your job is to understand what a survey is actually measuring and deliver the most useful analysis for whoever commissioned it — not to apply a generic report template.

      ## THE RIGHT WAY TO ANALYZE A SURVEY

      Step 1 — READ THE SURVEY ITSELF.
      Before anything else: read the title, description, and every question. Ask:
      - What is the central metric this survey is trying to measure? (time saved, satisfaction level, adoption rate, pain points, etc.)
      - Who will read this analysis? (team lead, HR, management, the respondents themselves?)
      - What decision or action should the analysis enable?

      Step 2 — FIND THE GROUPING VARIABLES.
      Look for questions that capture segments (department, role, experience level, location, product used, etc.).
      If grouping variables exist → cross-tabbing the central metric by those groups is ALWAYS valuable and should be done automatically, without being asked.
      Reason: overall averages hide the most important patterns. "Frontend saves 70%, QC saves 35%" is far more useful than "average 55%."

      Step 3 — FIND CROSS-QUESTION PATTERNS.
      Ask: which two (or more) questions, when combined, reveal something that neither shows alone?
      Examples:
      - High time savings + low quality rating in the same department → AI tools may be fast but unreliable there
      - High automation potential + low current usage → untapped opportunity
      - High satisfaction + high willingness to recommend + low actual daily usage → adoption barrier, not satisfaction issue
      Write ONE section per important cross-question pattern you find.

      Step 4 — DERIVE RECOMMENDATIONS FROM THE DATA.
      Recommendations must follow directly from the patterns found. No generic advice.
      Each recommendation: WHO does WHAT, by WHEN, with what measurable outcome.

      ## WRITING RULES
      - Write ALL content in #{lang_name}
      - Every sentence must contain a specific number, name, or finding. Zero vague generalities.
      - Concise: each paragraph = 2-3 sentences max.
      - Return ONLY valid JSON. Use \\n\\n for paragraph breaks. No markdown fences.
    SYS

    # ── Build all chart + cross-tab data BEFORE the AI call ────────────────
    # AI must see actual DB numbers to write an accurate, non-hallucinated analysis.
    completed_response_ids = survey.responses.completed.where(excluded: [false, nil]).pluck(:id)
    all_chart_data         = build_question_chart_data(survey, completed_response_ids)

    valid_q_ids     = survey.questions.pluck(:id).map(&:to_i).to_set
    choice_type_ids = survey.questions
                            .where(question_type: %w[single_choice dropdown])
                            .pluck(:id).map(&:to_i).to_set

    # Pre-extract cross-tab pairs from user context and build their data early
    pre_pairs         = pre_extracted_cross_tab_pairs(user_context, survey)
    pre_cross_tab_map = pre_pairs.any? ?
      build_cross_tab_data(survey, pre_pairs, completed_response_ids) : {}

    # Build compact per-question data summary for the AI prompt
    questions_data_summary = all_chart_data.map do |qd|
      q = questions_list.find { |qq| qq.id == qd["question_id"].to_i }
      next unless q
      pos  = questions_list.index(q) + 1
      line = "Q#{pos} (ID #{q.id}) [#{q.question_type}#{qd['subtype'] == 'pct' ? '/pct%' : ''}] #{q.title.truncate(70)}"
      case qd["type"]
      when "rating", "linear_scale", "nps"
        line += "\n  data: avg=#{qd['avg']}/#{qd['max']}, n=#{qd['total']}"
        dist = qd["distribution"]&.map { |d| "#{d['value']}:#{d['count']}" }&.join(", ")
        line += ", dist=[#{dist}]" if dist
      when "single_choice", "multiple_choice", "dropdown"
        top = qd["distribution"]&.sort_by { |d| -d["count"].to_i }&.first(5)
        line += "\n  data: n=#{qd['total']}, choices=#{top&.map { |d| "#{d['value'].to_s.truncate(30)}(#{d['count']})" }&.join(', ')}"
      end
      xt = pre_cross_tab_map[qd["question_id"].to_i]
      if xt
        groups_str = xt["groups"]&.map { |g|
          val = g["avg"] || g["pct"]
          "#{g['label'].to_s.truncate(20)}=#{val}"
        }&.join(", ")
        line += "\n  by #{xt['group_question'].to_s.truncate(30)}: #{groups_str}" if groups_str
      end
      line
    end.compact.join("\n\n")

    user_prompt = <<~PROMPT
      ## Survey to analyze
      Title: #{survey.title}
      #{survey.description.present? ? "Description: #{survey.description}" : ""}
      Responses: #{responses.count} | Date: #{Date.current.strftime("%d/%m/%Y")}

      ## Actual response data — USE THESE EXACT NUMBERS (computed from DB, not estimated)
      #{questions_data_summary.truncate(5000)}

      ## All survey questions (reference)
      #{questions_ref}

      #{context_block}

      ---
      Apply the 4-step analysis above using the actual data provided, then produce this JSON (ALL text in #{lang_name}):

      {
        "title": "Report title derived from survey purpose (not generic)",
        "subtitle": "#{Date.current.strftime("%m/%Y")} — #{responses.count} phản hồi",

        "executive_summary": "EXACTLY 2 paragraphs separated by \\n\\n. They must be DIFFERENT — never repeat the same sentence.\\nPara 1 (THE KEY FINDING): The single most important cross-question or cross-group insight with exact numbers from the data above. Must reference at least 2 questions together.\\nPara 2 (THE IMPLICATION): What should the reader DO with this finding? Who acts, how, and why now?",

        "key_metrics": {
          "response_count": #{responses.count},
          "sentiment_positive": "#{pos_from_analysis.presence || 'derive from data'}%",
          "sentiment_negative": "#{neg_from_analysis.presence || 'derive from data'}%",
          "top_concern": "The most critical finding in one sentence — specific and data-backed"
        },

        "sections": [
          <Write ONLY as many sections as genuinely distinct insights the data supports.
           Rule: 1 section per key cross-question pattern or subgroup gap found in Step 3.
           #{questions_list.size <= 4 ? "This survey has #{questions_list.size} questions — write 1–2 sections max. Do NOT pad." : "Write 2–4 sections. Stop when you run out of real insights."}
           Each section must answer a different analytical question. Never split one finding into two sections.
           Format: {"heading": "Name the INSIGHT (e.g. 'Frontend tiết kiệm gấp đôi QC — khoảng cách 35%')", "content": "2 paragraphs max. Cross-group/cross-question finding with exact numbers.", "key_finding": "One-sentence 'so what' — actionable."}
          >
        ],

        "recommendations": [
          {
            "priority": "high|medium|low",
            "action": "Specific: who + what + by when",
            "rationale": "Cite which questions and what data led to this",
            "expected_impact": "Measurable improvement expected"
          }
        ],

        "conclusion": "1 sentence — forward-looking, tied to the survey's central purpose.",

        "relevant_question_ids": [
          <Question IDs to render as charts.
           INCLUDE: outcome metrics (ratings, scales, %-estimates, multi-choice with real variance)
           SKIP: name/identity fields, pure grouping variables (department etc. — they appear as cross-tab axis instead), questions with zero variance (e.g. 100% chose one option)>
        ],

        "cross_tab_pairs": [
          <Based on Step 2 of your analysis: for EVERY grouping variable you found, pair it with each key outcome metric.
           Do this automatically — do not wait to be asked.
           Format: {"target_id": <outcome question ID>, "group_by_id": <grouping question ID>, "label": "Short label e.g. 'Tiết kiệm thời gian theo bộ phận'"}
           Rules: group_by_id must be single_choice or dropdown. Max 5 pairs total. Prioritize the pairs that show the biggest expected variance.>
        ],

        "chart_insights": {
          "<question_id string>": "1-2 sentences. Most important number + what it means. If cross-tab exists for this question, lead with the biggest gap between subgroups."
        }
      }

      Hard constraints:
      - Sections: #{questions_list.size <= 4 ? "1–2 only (small survey — do NOT pad)" : "2–4 only"}. Each answers a DIFFERENT analytical question. No repetition.
      - Recommendations: #{questions_list.size <= 4 ? "1–2" : "2–3"} only, by impact.
      - executive_summary paragraphs must NOT be identical or near-identical.
      - Every number you write MUST appear in the "Actual response data" section above. Do not invent numbers.
      - #{user_context ? "Requester's focus: \"#{user_context.truncate(600)}\"" : "No additional focus — derive insights from the data."}
    PROMPT

    result_text = ClaudeService.opus_long.call(
      system_prompt: system_prompt,
      user_prompt:   user_prompt,
      max_tokens:    8192
    )

    result = parse_json_response(result_text)

    # Filter chart_data to AI-selected relevant questions
    relevant_ids = Array(result["relevant_question_ids"]).map(&:to_i).select(&:positive?)
    chart_data   = relevant_ids.any? ?
      all_chart_data.select { |d| relevant_ids.include?(d["question_id"].to_i) } :
      all_chart_data.dup

    # Merge AI-provided chart insights
    chart_insights = result.delete("chart_insights") || {}
    chart_data.each do |qd|
      insight = chart_insights[qd["question_id"].to_s] || chart_insights[qd["question_id"].to_i.to_s]
      qd["insight"] = insight if insight.present?
    end

    # Merge AI-suggested cross-tab pairs with pre-extracted ones (validated)
    ai_pairs = Array(result.delete("cross_tab_pairs")).select { |p|
      p.is_a?(Hash) &&
        p["target_id"].present? && p["group_by_id"].present? &&
        valid_q_ids.include?(p["target_id"].to_i) &&
        valid_q_ids.include?(p["group_by_id"].to_i) &&
        choice_type_ids.include?(p["group_by_id"].to_i)
    }
    cross_tab_pairs = (pre_pairs + ai_pairs)
                      .uniq { |p| "#{p['target_id']}_#{p['group_by_id']}" }
                      .first(5)

    # Ensure cross-tab target questions are in chart_data
    if cross_tab_pairs.any?
      extra_ids = cross_tab_pairs.map { |p| p["target_id"].to_i }
      missing   = all_chart_data.select { |d|
        extra_ids.include?(d["question_id"].to_i) && chart_data.none? { |c| c["question_id"] == d["question_id"] }
      }
      chart_data += missing
    end

    # Build cross-tab data for ALL final pairs (covers newly AI-suggested pairs too)
    if cross_tab_pairs.any? && completed_response_ids.any?
      cross_tab_map = build_cross_tab_data(survey, cross_tab_pairs, completed_response_ids)
      chart_data.each do |qd|
        xt = cross_tab_map[qd["question_id"].to_i]
        qd["cross_tab"] = xt if xt
      end
    end

    # Remove grouping questions from standalone charts (they only serve as cross-tab axis)
    group_q_ids = cross_tab_pairs.map { |p| p["group_by_id"].to_i }.uniq
    chart_data.reject! { |d| group_q_ids.include?(d["question_id"].to_i) }

    # Order: cross-tab target questions first (money charts), then remaining in relevant_ids order
    cross_tab_target_ids = cross_tab_pairs.map { |p| p["target_id"].to_i }
    priority_order       = (cross_tab_target_ids + relevant_ids).uniq
    chart_data.sort_by! { |d| priority_order.index(d["question_id"].to_i) || 999 }

    result["chart_data"] = chart_data

    # Store metadata alongside the report content
    result["_meta"] = {
      "format"       => report_format,
      "language"     => language,
      "user_context" => user_context,
      "generated_at" => Time.current.iso8601
    }

    AiAnalysisResult.create!(
      workspace:      job.workspace,
      ai_job:         job,
      result_type:    "executive_report",
      resource_type:  "Survey",
      resource_id:    survey.id,
      output:         result,
      credits_cost:   15,
      response_count: responses.count
    )

    job.complete!(result)
  rescue => e
    if TRANSIENT_ERRORS.any? { |klass| e.is_a?(klass) }
      raise
    else
      job.fail!(e.message)
    end
  end

  private

  def build_question_chart_data(survey, completed_response_ids = nil)
    completed_response_ids ||= survey.responses.completed.where(excluded: [false, nil]).pluck(:id)
    return [] if completed_response_ids.empty?

    survey.questions.order(:position).filter_map do |q|
      base = Answer.where(question: q, response_id: completed_response_ids)

      case q.question_type.to_sym
      when :single_choice, :multiple_choice, :dropdown
        total = base.count
        next if total == 0
        # option_ids is jsonb — use @> with a JSON array literal
        options = q.question_options.order(:position).map do |opt|
          # option_ids stores string IDs e.g. ["263"], not integers [263]
          count = base.where("option_ids @> ?", [opt.id.to_s].to_json).count
          { "id" => opt.id, "label" => opt.label, "count" => count,
            "pct" => (count.to_f / total * 100).round(1) }
        end
        { "question_id" => q.id, "question" => q.title,
          "type" => q.question_type.to_s, "total" => total, "options" => options }

      when :rating, :nps, :linear_scale
        nums = base.where.not(numeric_value: nil).pluck(:numeric_value).map(&:to_i)
        next if nums.empty?
        max_val = if q.nps?
                    10
                  elsif q.question_type == "linear_scale"
                    q.settings&.dig("max_value")&.to_i.then { |v| v&.positive? ? v : 10 }
                  else
                    5
                  end
        avg = (nums.sum.to_f / nums.size).round(1)
        dist = (1..max_val).map { |v| { "value" => v, "count" => nums.count(v) } }
        { "question_id" => q.id, "question" => q.title,
          "type" => q.question_type.to_s, "total" => nums.size,
          "avg" => avg, "max" => max_val, "distribution" => dist }

      when :short_text, :long_text
        texts = base.where.not(text_value: [nil, ""]).pluck(:text_value)
        next if texts.empty?
        # Try to extract leading numeric values (e.g. "50%", "50-60%", "~40%")
        nums = texts.filter_map { |t| t.to_s.gsub(/[~≈]/, "").scan(/\d+(?:\.\d+)?/).first&.to_f }
                    .select { |n| n > 0 && n <= 100 }
        if nums.size >= texts.size * 0.5
          # Numeric text question (e.g. % time saved) — render as scale chart
          avg     = (nums.sum / nums.size).round(1)
          max_val = 100
          dist    = [[0,20],[21,40],[41,60],[61,80],[81,100]].map do |lo, hi|
            { "value" => "#{lo}–#{hi}%", "count" => nums.count { |n| n >= lo && n <= hi } }
          end
          { "question_id" => q.id, "question" => q.title,
            "type" => "linear_scale", "subtype" => "pct",
            "total" => nums.size, "avg" => avg, "max" => max_val, "distribution" => dist }
        else
          { "question_id" => q.id, "question" => q.title,
            "type" => q.question_type.to_s, "total" => texts.size }
        end
      end
    end.compact
  end

  # Parse cross-tab requests directly from user_context string.
  # Handles patterns: "Q7 × Q2", "Q7 x Q2", "Cross-tab theo Q2", "theo Q2 (bộ phận)"
  # Returns [{target_id, group_by_id, label}] ready for build_cross_tab_data.
  def pre_extracted_cross_tab_pairs(context, survey)
    return [] unless context.present?

    questions_by_pos = survey.questions.order(:position)
                             .each_with_index.to_h { |q, i| [i + 1, q] }
    pairs = []
    seen  = Set.new

    # Helper to register a pair (target_pos × group_pos)
    register = ->(tp, gp) {
      target_q = questions_by_pos[tp]
      group_q  = questions_by_pos[gp]
      return unless target_q && group_q
      return unless %w[rating nps linear_scale short_text long_text].include?(target_q.question_type)
      return unless %w[single_choice dropdown].include?(group_q.question_type)
      key = "#{target_q.id}_#{group_q.id}"
      return if seen.include?(key)
      seen << key
      pairs << {
        "target_id"   => target_q.id,
        "group_by_id" => group_q.id,
        "label"       => "#{target_q.title.truncate(35)} theo #{group_q.title.truncate(25)}"
      }
    }

    # Pattern 1: explicit "Qx × Qy" or "Qx x Qy"
    context.scan(/Q(\d+)\s*[×x]\s*Q(\d+)/i) do |a, b|
      register.call(a.to_i, b.to_i)
      register.call(b.to_i, a.to_i)  # try both directions
    end

    # Pattern 2: "theo Q\d+" — find most-mentioned grouping Q, pair with nearby Qs
    group_counts = context.scan(/(?:theo|by)\s+Q(\d+)/i).flatten.map(&:to_i).tally
    group_counts.sort_by { |_, c| -c }.first(2).each do |group_pos, _|
      group_q = questions_by_pos[group_pos]
      next unless group_q && %w[single_choice dropdown].include?(group_q.question_type)
      # All Qs explicitly mentioned in context → try pairing with this group
      context.scan(/\bQ(\d+)\b/).flatten.map(&:to_i).uniq.reject { |p| p == group_pos }.each do |tp|
        register.call(tp, group_pos)
      end
    end

    pairs.first(5)
  end

  # Build cross-tab data: for each pair {target_id, group_by_id}, compute avg/distribution
  # of the target question broken down by each option of the grouping question.
  def build_cross_tab_data(survey, pairs, completed_response_ids)
    result = {}
    pairs.each do |pair|
      target_q = survey.questions.find_by(id: pair["target_id"].to_i)
      group_q  = survey.questions.find_by(id: pair["group_by_id"].to_i)
      next unless target_q && group_q

      group_options = group_q.question_options.order(:position)
      max_val = if target_q.nps?
                  10
                elsif target_q.question_type == "linear_scale"
                  target_q.settings&.dig("max_value")&.to_i.then { |v| v&.positive? ? v : 10 }
                elsif %w[short_text long_text].include?(target_q.question_type)
                  100  # percentage questions
                else
                  5
                end

      groups = group_options.filter_map do |opt|
        # Response IDs where respondent chose this option in the grouping question
        group_resp_ids = Answer.where(question: group_q, response_id: completed_response_ids)
                               .where("option_ids @> ?", [opt.id.to_s].to_json)
                               .pluck(:response_id)
        next if group_resp_ids.empty?

        target_base = Answer.where(question: target_q, response_id: group_resp_ids)

        case target_q.question_type.to_sym
        when :rating, :nps, :linear_scale
          nums = target_base.where.not(numeric_value: nil).pluck(:numeric_value).map(&:to_i)
          next if nums.empty?
          avg = (nums.sum.to_f / nums.size).round(1)
          { "label" => opt.label.truncate(30), "avg" => avg, "total" => nums.size, "max" => max_val }
        when :single_choice, :multiple_choice, :dropdown
          total = target_base.count
          next if total == 0
          top_opts = target_q.question_options.order(:position).map do |topt|
            cnt = target_base.where("option_ids @> ?", [topt.id.to_s].to_json).count
            { "option" => topt.label.truncate(30), "pct" => (cnt.to_f / total * 100).round(1) }
          end.max_by { |o| o["pct"] }
          { "label" => opt.label.truncate(30), "top_option" => top_opts["option"], "pct" => top_opts["pct"], "total" => total }
        when :short_text, :long_text
          # Numeric text (% estimates): extract leading number from each answer
          texts = target_base.where.not(text_value: [nil, ""]).pluck(:text_value)
          next if texts.empty?
          nums = texts.filter_map { |t| t.to_s.gsub(/[~≈]/, "").scan(/\d+(?:\.\d+)?/).first&.to_f }
                      .select { |n| n > 0 && n <= 100 }
          next if nums.size < texts.size * 0.4  # skip if not mostly numeric
          avg = (nums.sum / nums.size).round(1)
          { "label" => opt.label.truncate(30), "avg" => avg, "total" => nums.size, "max" => 100 }
        end
      end.compact

      next if groups.empty?
      result[target_q.id] = {
        "label"          => (pair["label"] || "So sánh theo nhóm").truncate(60),
        "group_question" => group_q.title.truncate(60),
        "type"           => target_q.question_type.to_s,
        "max"            => max_val,
        "groups"         => groups.sort_by { |g| -(g["avg"] || g["pct"] || 0) }
      }
    end
    result
  end

  def parse_json_response(text)
    clean    = text.gsub(/\A\s*```(?:json)?\s*/i, "").gsub(/\s*```\s*\z/, "").strip
    json_str = clean.match(/\{.*\}/m)&.to_s || clean

    begin
      return JSON.parse(json_str)
    rescue JSON::ParserError
    end

    begin
      return JSON.parse(fix_json_strings(json_str))
    rescue JSON::ParserError
    end

    begin
      return JSON.parse(json_str.gsub(/[\x00-\x1F\x7F]/, ''))
    rescue JSON::ParserError => e
      raise "Could not parse AI response as JSON: #{e.message.truncate(200)}"
    end
  end

  def fix_json_strings(s)
    out    = String.new(encoding: "UTF-8")
    in_str = false
    i      = 0
    while i < s.length
      c = s[i]
      if in_str
        case c
        when "\\"
          out << c << (s[i + 1] || "")
          i += 2
          next
        when '"'
          in_str = false
          out << c
        when "\n" then out << '\\n'
        when "\r" then out << '\\r'
        when "\t" then out << '\\t'
        else
          out << c
        end
      else
        out << c
        in_str = true if c == '"'
      end
      i += 1
    end
    out
  end
end
