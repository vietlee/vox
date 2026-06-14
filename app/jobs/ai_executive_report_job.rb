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

    # Parse semantic intent from user_context to inject as hard directives
    focus_intent  = user_context ? parse_focus_intent(user_context, survey) : {}

    context_block = user_context ? <<~CTX : ""
      ## ⚡ PRIORITY DIRECTIVE — FROM REPORT REQUESTER
      The person who commissioned this report wrote: "#{user_context}"

      #{focus_intent[:metric_desc].present? ? "FOCUS METRIC: They want to see \"#{focus_intent[:metric_desc]}\"#{focus_intent[:dimension_desc].present? ? " broken down by \"#{focus_intent[:dimension_desc]}\"" : ""}." : ""}
      #{focus_intent[:quick_report] ? "SCOPE: They asked for a QUICK report — write only 1–2 sections max, 2 recommendations max. Do not pad." : ""}
      #{focus_intent[:matched_target_q].present? ? "MATCHED QUESTION: Q#{focus_intent[:matched_target_pos]} (\"#{focus_intent[:matched_target_q].title.truncate(60)}\") is the primary metric to highlight." : ""}
      #{focus_intent[:matched_group_q].present? ? "MATCHED GROUPING: Q#{focus_intent[:matched_group_pos]} (\"#{focus_intent[:matched_group_q].title.truncate(60)}\") is the grouping dimension to cross-tab against." : ""}

      HARD RULES based on this request:
      - The executive summary MUST open with the specific insight they asked for.
      - Sections must center on this focus — deprioritize unrelated questions.
      - relevant_question_ids MUST include the matched metric question ID(s) above.
      - cross_tab_pairs MUST include the matched target × group pair above (if both found).
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
    # Also inject pair from semantic focus_intent if found
    pre_pairs = pre_extracted_cross_tab_pairs(user_context, survey)
    if focus_intent[:matched_target_q] && focus_intent[:matched_group_q]
      intent_pair = {
        "target_id"   => focus_intent[:matched_target_q].id,
        "group_by_id" => focus_intent[:matched_group_q].id,
        "label"       => "#{focus_intent[:matched_target_q].title.truncate(35)} theo #{focus_intent[:matched_group_q].title.truncate(25)}"
      }
      key = "#{intent_pair['target_id']}_#{intent_pair['group_by_id']}"
      pre_pairs.unshift(intent_pair) unless pre_pairs.any? { |p| "#{p['target_id']}_#{p['group_by_id']}" == key }
    end
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
      #{context_block}
      ## Survey to analyze
      Title: #{survey.title}
      #{survey.description.present? ? "Description: #{survey.description}" : ""}
      Responses: #{responses.count} | Date: #{Date.current.strftime("%d/%m/%Y")}

      ## Actual response data — USE THESE EXACT NUMBERS (computed from DB, not estimated)
      #{questions_data_summary.truncate(5000)}

      ## All survey questions (reference)
      #{questions_ref}

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

        "charts": [
          <VISUAL PLAN — you decide which charts to show, what type, what order.
           This replaces the old relevant_question_ids + cross_tab_pairs approach.

           For each chart, output one object:
           {
             "question_id": <int — the question whose data to plot. null if this is a pure cross-tab comparison>,
             "chart_type": <see CHART TYPE GUIDE below>,
             "title": "Short AI-written title ≤7 words (not the raw question text)",
             "span": "full|half",
             "insight": "1-2 sentences: most important number + what it means",
             "cross_tab_by": <group_by question ID (single_choice/dropdown) — OR null if no cross-tab>
           }

           CHART TYPE GUIDE — pick the most insightful, not the default:
           - "doughnut"    — best for: single_choice with ≤6 options when proportions are the story
           - "hbar"        — best for: multi-choice, ranking, top-N options, or any choice >6 options
           - "bar"         — best for: distributions where order/trend matters (e.g. 1-10 scores)
           - "dist_bar"    — best for: numeric % estimates grouped into buckets (pct savings, automation)
           - "rating_dist" — best for: rating/linear_scale 1-5 or 1-10 when individual score distribution matters
           - "nps"         — ONLY for 0-10 satisfaction/recommendation questions (groups into 3 colored zones)
           - "grouped_bar" — best for: comparing a metric across departments/roles — REQUIRES cross_tab_by
           - "number"      — best for: single KPI where one number tells the story (avg, %, count)
           - "quotes"      — best for: long_text open responses where themes/quotes convey meaning

           CROSS-TAB RULE: if a grouping question exists (department, role, etc.) AND a key metric exists,
           ALWAYS create a "grouped_bar" chart showing that metric broken down by group.
           This is the "money chart" — put it first or second in the array.

           SELECTION RULES:
           - Order charts from most to least important for the requester's question
           - "half" span for charts that stand alone well (doughnut, number, rating_dist)
           - "full" span for complex charts (grouped_bar, hbar with many options, dist_bar, quotes)
           - SKIP: pure identity fields (name, email), grouping-only questions, zero-variance questions
           - MAX 8 charts total. Cut anything that doesn't change a decision.
           #{focus_intent[:matched_target_q] ? "- FIRST CHART MUST be about question ID #{focus_intent[:matched_target_q].id}#{focus_intent[:matched_group_q] ? " with cross_tab_by=#{focus_intent[:matched_group_q].id}" : ""}" : ""}
          >
        ]
      }

      Hard constraints:
      - Sections: #{focus_intent[:quick_report] ? "1 only (quick report requested)" : questions_list.size <= 4 ? "1–2 only (small survey — do NOT pad)" : "2–4 only"}. Each answers a DIFFERENT analytical question. No repetition.
      - Recommendations: #{focus_intent[:quick_report] ? "1–2" : questions_list.size <= 4 ? "1–2" : "2–3"} only, by impact.
      - executive_summary paragraphs must NOT be identical or near-identical.
      - Every number you write MUST appear in the "Actual response data" section above. Do not invent numbers.
      - charts array must use actual question IDs from the survey (check ## All survey questions above).
      - cross_tab_by must be a single_choice or dropdown question ID.
    PROMPT

    result_text = ClaudeService.opus_long.call(
      system_prompt: system_prompt,
      user_prompt:   user_prompt,
      max_tokens:    8192
    )

    result = parse_json_response(result_text)

    # ── Process new "charts" visual plan from AI ──────────────────────────────
    ai_charts = Array(result.delete("charts")).select { |c| c.is_a?(Hash) }

    # Also handle legacy format (relevant_question_ids) if AI returns old format
    if ai_charts.empty? && result["relevant_question_ids"].present?
      ai_charts = Array(result.delete("relevant_question_ids")).map(&:to_i).select(&:positive?).map { |id|
        { "question_id" => id, "chart_type" => nil, "title" => nil, "span" => "half", "insight" => nil }
      }
    end

    # Validate question IDs in charts
    ai_charts.select! { |c| c["question_id"].nil? || valid_q_ids.include?(c["question_id"].to_i) }

    # Inject semantic focus intent as first chart if AI missed it
    if focus_intent[:matched_target_q] && focus_intent[:matched_group_q]
      fi_qid = focus_intent[:matched_target_q].id
      fi_gid = focus_intent[:matched_group_q].id
      unless ai_charts.any? { |c| c["question_id"].to_i == fi_qid && c["cross_tab_by"].to_i == fi_gid }
        ai_charts.unshift(
          "question_id"  => fi_qid,
          "chart_type"   => "grouped_bar",
          "title"        => "#{focus_intent[:matched_target_q].title.truncate(40)} theo #{focus_intent[:matched_group_q].title.truncate(25)}",
          "span"         => "full",
          "cross_tab_by" => fi_gid
        )
      end
    end

    # Collect all cross-tab pairs needed from the visual plan
    plan_cross_tab_pairs = ai_charts.filter_map { |c|
      next unless c["cross_tab_by"].present? && c["question_id"].present?
      tid = c["question_id"].to_i
      gid = c["cross_tab_by"].to_i
      next unless valid_q_ids.include?(tid) && valid_q_ids.include?(gid) && choice_type_ids.include?(gid)
      { "target_id" => tid, "group_by_id" => gid, "label" => c["title"].to_s }
    }.uniq { |p| "#{p['target_id']}_#{p['group_by_id']}" }

    # Merge with pre_pairs from semantic intent
    all_cross_tab_pairs = (pre_pairs + plan_cross_tab_pairs)
                          .uniq { |p| "#{p['target_id']}_#{p['group_by_id']}" }
                          .first(8)

    # Build cross-tab data for all pairs
    cross_tab_map = {}
    if all_cross_tab_pairs.any? && completed_response_ids.any?
      cross_tab_map = build_cross_tab_data(survey, all_cross_tab_pairs, completed_response_ids)
    end

    # Build chart_data in AI-specified order, applying AI overrides
    chart_data_by_qid = all_chart_data.index_by { |d| d["question_id"].to_i }

    chart_data = ai_charts.filter_map { |c|
      qid = c["question_id"]&.to_i
      next if qid.nil? || qid == 0  # skip pure cross-tab-only specs (handled via cross_tab_by)

      base = chart_data_by_qid[qid]&.dup || next

      # Apply AI overrides
      base["ai_chart_type"] = c["chart_type"].presence
      base["ai_title"]      = c["title"].presence
      base["ai_span"]       = c["span"].presence || "half"
      base["insight"]       = c["insight"].presence if c["insight"].present?

      # Attach cross-tab data if requested
      if c["cross_tab_by"].present?
        gid = c["cross_tab_by"].to_i
        xt  = cross_tab_map[qid]
        # cross_tab_map is keyed by target_id; find matching group
        if xt.nil?
          # Try to find in all_cross_tab_pairs
          pair_key = all_cross_tab_pairs.find { |p| p["target_id"].to_i == qid && p["group_by_id"].to_i == gid }
          xt = cross_tab_map[qid] if pair_key
        end
        base["cross_tab"] = xt if xt
      end

      base
    }.compact

    # If AI returned nothing useful, fall back to all chart data
    chart_data = all_chart_data.dup if chart_data.empty?

    # Merge pre-built cross-tab from pre_pairs (for any charts not already handled above)
    pre_cross_tab_map.each do |qid, xt|
      cd = chart_data.find { |d| d["question_id"].to_i == qid }
      cd["cross_tab"] ||= xt if cd
    end

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
  # ── Semantic intent parser ─────────────────────────────────────────────────
  # Parses natural language user_context to extract focus metric + grouping dimension
  # Returns hash with matched questions and descriptors for prompt injection
  def parse_focus_intent(context, survey)
    return {} unless context.present?

    questions = survey.questions.includes(:question_options).order(:position)
    metric_qs = questions.select { |q| %w[rating nps linear_scale short_text long_text].include?(q.question_type) }
    group_qs  = questions.select { |q| %w[single_choice dropdown].include?(q.question_type) }

    norm = ->(s) {
      s.to_s.downcase
       .gsub(/[àáạảãâầấậẩẫăằắặẳẵ]/, 'a')
       .gsub(/[èéẹẻẽêềếệểễ]/, 'e')
       .gsub(/[ìíịỉĩ]/, 'i')
       .gsub(/[òóọỏõôồốộổỗơờớợởỡ]/, 'o')
       .gsub(/[ùúụủũưừứựửữ]/, 'u')
       .gsub(/[ỳýỵỷỹ]/, 'y')
       .gsub(/đ/, 'd')
       .gsub(/[^a-z0-9\s]/, ' ')
       .gsub(/\s+/, ' ').strip
    }

    ctx_norm = norm.call(context)

    # Detect "quick report" intent
    quick_report = ctx_norm.match?(/\b(nhanh|toc do|tom tat|ngan gon|brief|quick|summary)\b/)

    # Extract target and dimension phrases from intent patterns:
    # "X giữa [các] Y", "X theo Y", "chart/biểu đồ X theo Y", "so sánh X [theo/giữa] Y"
    target_phrase = nil
    group_phrase  = nil

    intent_patterns = [
      /(?:chart|bieu do|so sanh|hien thi|xem|phan tich)\s+(.+?)\s+(?:giua(?: cac)?|theo|phan chia theo|breakdown)\s+(.+)/,
      /(.+?)\s+(?:giua(?: cac)?|theo tung|theo)\s+(.+?)\s*$/,
      /(.+?)\s+(?:phan loai|chia)\s+(?:theo|by)\s+(.+)/,
    ]
    intent_patterns.each do |pat|
      m = ctx_norm.match(pat)
      if m
        target_phrase = m[1].strip.gsub(/^(cua|ve|cho)\s+/, '')
        group_phrase  = m[2].strip.gsub(/^(cac|cua|moi)\s+/, '')
        break
      end
    end

    # Score function: count matching words between phrase and question title
    score_q = ->(q, phrase) {
      return 0 unless phrase
      q_norm = norm.call(q.title)
      words  = phrase.split(/\s+/).select { |w| w.length >= 3 }
      words.count { |w| q_norm.include?(w) }
    }

    # Find best matching metric question
    matched_target_q = if target_phrase
      best = metric_qs.max_by { |q| score_q.call(q, target_phrase) }
      best if best && score_q.call(best, target_phrase) > 0
    end

    # Find best matching group question — also check dimension keywords
    dept_keywords = %w[bo phan phong ban department nhom team vai tro role]
    matched_group_q = if group_phrase
      # First try phrase matching
      best = group_qs.max_by { |q| score_q.call(q, group_phrase) }
      if best && score_q.call(best, group_phrase) > 0
        best
      else
        # Fallback: check if group_phrase contains department-like keywords
        is_dept = dept_keywords.any? { |kw| group_phrase.include?(kw) }
        if is_dept
          group_qs.find { |q| dept_keywords.any? { |kw| norm.call(q.title).include?(kw) } }
        end
      end
    else
      # No explicit group phrase — check context for dept keywords
      if dept_keywords.any? { |kw| ctx_norm.include?(kw) }
        group_qs.find { |q| dept_keywords.any? { |kw| norm.call(q.title).include?(kw) } }
      end
    end

    # If we have a group but no target yet, find best metric from context keywords
    if matched_group_q && !matched_target_q
      ctx_words = ctx_norm.split(/\s+/).select { |w| w.length >= 4 }
      best = metric_qs.max_by { |q| q_norm = norm.call(q.title); ctx_words.count { |w| q_norm.include?(w) } }
      matched_target_q = best if best && ctx_words.any? { |w| norm.call(best.title).include?(w) }
    end

    positions = questions.each_with_index.to_h { |q, i| [q.id, i + 1] }

    {
      quick_report:        quick_report,
      metric_desc:         target_phrase,
      dimension_desc:      group_phrase,
      matched_target_q:    matched_target_q,
      matched_group_q:     matched_group_q,
      matched_target_pos:  matched_target_q ? positions[matched_target_q.id] : nil,
      matched_group_pos:   matched_group_q  ? positions[matched_group_q.id]  : nil,
    }
  end

  def pre_extracted_cross_tab_pairs(context, survey)
    return [] unless context.present?

    questions_by_pos = survey.questions.order(:position)
                             .each_with_index.to_h { |q, i| [i + 1, q] }
    pairs = []
    seen  = Set.new

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
      register.call(b.to_i, a.to_i)
    end

    # Pattern 2: "theo Q\d+"
    group_counts = context.scan(/(?:theo|by)\s+Q(\d+)/i).flatten.map(&:to_i).tally
    group_counts.sort_by { |_, c| -c }.first(2).each do |group_pos, _|
      group_q = questions_by_pos[group_pos]
      next unless group_q && %w[single_choice dropdown].include?(group_q.question_type)
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
