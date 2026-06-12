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

    system_prompt = <<~SYS.strip
      You are a senior strategic analyst writing board-ready executive reports from survey data.
      Reports go directly into leadership decision meetings — every sentence must earn its place.

      ## HOW TO THINK (do this before writing anything)
      Step 1 — Understand the survey's PURPOSE: What decision does leadership need to make? What question is this survey trying to answer?
      Step 2 — Find CROSS-CUTTING INSIGHTS: What do you learn by combining multiple questions that no single question shows alone? (e.g. "Department X saves 2× more time than Y — and they also rate AI quality 1.5 points higher. That's not coincidence.")
      Step 3 — Identify the STRATEGIC GAP: What is the single most important thing leadership doesn't know yet, but needs to?
      Step 4 — Write with that framing. Sections = strategic questions answered with data, NOT question-by-question summaries.

      ## STYLE RULES
      - Write ALL content in #{lang_name}
      - Ruthlessly concise: each paragraph = 2-3 sentences. No fluff.
      - Every sentence must contain a specific number or finding. Zero vague generalities.
      - Recommendations must name WHO does WHAT by WHEN with measurable outcome.
      - Return ONLY valid JSON. Use \\n\\n for paragraph breaks. No markdown, no code fences.
    SYS

    user_prompt = <<~PROMPT
      ## Survey
      Title: #{survey.title}
      #{survey.description.present? ? "Purpose: #{survey.description}" : ""}
      Responses: #{responses.count} | Date: #{Date.current.strftime("%d/%m/%Y")}

      ## Pre-computed Analysis Data (factual foundation — use exact numbers)
      #{analysis.to_json.truncate(4000)}

      ## Survey Questions (for cross-tab and ID reference)
      #{survey.questions.order(:position).map { |q| "ID #{q.id} Q#{survey.questions.order(:position).index(q)+1}: [#{q.question_type}] #{q.title}" }.join("\n")}

      #{context_block}

      ## Your task
      Before selecting cross_tab_pairs and writing sections, ask yourself:
      - What is the most important comparison this survey enables? (e.g. outcome metric × demographic group)
      - Which two questions, when combined, reveal something that neither shows alone?
      - What would a CEO want to know that requires looking across multiple questions?

      Then write the report JSON. ALL text in #{lang_name}.

      {
        "title": "Professional report title",
        "subtitle": "Scope/period — #{Date.current.strftime("%m/%Y")}",

        "executive_summary": "EXACTLY 2 paragraphs. Para 1: the single most important cross-cutting finding with exact numbers (NOT just the overall average — find the insight that requires combining data). Para 2: what it means for leadership action. Use \\n\\n between paragraphs.",

        "key_metrics": {
          "response_count": #{responses.count},
          "sentiment_positive": "#{pos_from_analysis.presence || 'derive from data'}%",
          "sentiment_negative": "#{neg_from_analysis.presence || 'derive from data'}%",
          "top_concern": "Most critical issue — specific, with data"
        },

        "sections": [
          {
            "heading": "Section title — name the INSIGHT, not the question topic",
            "content": "2 paragraphs MAX. Lead with the cross-cutting finding. Cite specific numbers. Explain what it means strategically.",
            "key_finding": "One sentence — the 'so what' of this section"
          }
        ],

        "recommendations": [
          {
            "priority": "high|medium|low",
            "action": "WHO does WHAT by WHEN",
            "rationale": "Why — cite specific question IDs and findings",
            "expected_impact": "Measurable outcome expected"
          }
        ],

        "conclusion": "1 forward-looking sentence.",

        "relevant_question_ids": [
          <IDs of questions worth charting. Rules:
           - Include outcome metrics (ratings, scales, numeric estimates) and multi-choice breakdowns
           - SKIP: name/identity questions, pure grouping variables (e.g. department) — those appear as cross-tab axis, not standalone
           - SKIP: binary yes/no questions with 100% one answer (no variance = no insight)
           - Include questions where cross-tab comparison reveals something meaningful>
        ],

        "cross_tab_pairs": [
          <PROACTIVELY identify the most strategically valuable comparisons. Do NOT wait to be asked.
           Ask: "What grouping variable (department, role, experience level) would most change leadership's decision if one subgroup looked very different?"
           For each valuable comparison: {"target_id": <outcome question ID>, "group_by_id": <grouping question ID>, "label": "Tên insight ngắn gọn"}
           Max 5 pairs. group_by_id MUST be a single_choice or dropdown question.
           Good examples: time savings × department, satisfaction × department, barrier frequency × department>
        ],

        "chart_insights": {
          "<question_id as string>": "1-2 sentences: most important number + strategic implication. If cross-tab exists, mention the biggest gap between subgroups."
        }
      }

      Hard constraints:
      - EXACTLY 3-4 sections. Each = 2 paragraphs max.
      - EXACTLY 3 recommendations, ordered by impact.
      - sentiment values: use exact % from analysis data, numeric only.
      - Sections must be insight-driven (answer a strategic question), NOT question-by-question summaries.
      - #{user_context ? "The requester's focus: \"#{user_context.truncate(500)}\" — address these points directly in the analysis." : "Derive the most important strategic insights from the data."}
    PROMPT

    result_text = ClaudeService.opus_long.call(
      system_prompt: system_prompt,
      user_prompt:   user_prompt,
      max_tokens:    8192
    )

    result = parse_json_response(result_text)

    # Attach real per-question chart data from DB, filtered by AI-selected relevant questions
    completed_response_ids = survey.responses.completed.where(excluded: [false, nil]).pluck(:id)
    all_chart_data = build_question_chart_data(survey, completed_response_ids)
    relevant_ids   = Array(result["relevant_question_ids"]).map(&:to_i).select(&:positive?)
    chart_data = relevant_ids.any? ?
      all_chart_data.select { |d| relevant_ids.include?(d["question_id"].to_i) } :
      all_chart_data

    # Merge AI-provided chart insights into each chart entry
    chart_insights = result.delete("chart_insights") || {}
    chart_data.each do |qd|
      insight = chart_insights[qd["question_id"].to_s] || chart_insights[qd["question_id"].to_i.to_s]
      qd["insight"] = insight if insight.present?
    end

    # Build cross-tab breakdowns:
    # 1. Pre-extract from user context (regex — reliable, doesn't depend on AI)
    # 2. Merge with AI-provided pairs
    pre_pairs = pre_extracted_cross_tab_pairs(user_context, survey)
    ai_pairs  = Array(result.delete("cross_tab_pairs")).select { |p|
      p.is_a?(Hash) && p["target_id"].present? && p["group_by_id"].present?
    }
    cross_tab_pairs = (pre_pairs + ai_pairs)
                      .uniq { |p| "#{p['target_id']}_#{p['group_by_id']}" }
                      .first(5)

    # Ensure cross-tab target questions are included in chart_data even if AI omitted them
    if cross_tab_pairs.any?
      extra_ids = cross_tab_pairs.map { |p| p["target_id"].to_i }
      missing   = all_chart_data.select { |d| extra_ids.include?(d["question_id"].to_i) && chart_data.none? { |c| c["question_id"] == d["question_id"] } }
      chart_data += missing
    end

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
