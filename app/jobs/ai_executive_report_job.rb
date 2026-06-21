require "net/http"

class AiExecutiveReportJob < ApplicationJob
  queue_as :ai

  TRANSIENT_ERRORS = [Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT].freeze

  retry_on(*TRANSIENT_ERRORS, wait: 20.seconds, attempts: 2) do |job_instance, error|
    ai_job = AiJob.find_by(id: job_instance.arguments.first)
    ai_job&.fail!("Network timeout after retries: #{error.message.truncate(200)}")
  end

  # ═══════════════════════════════════════════════════════════════════════════
  #  Architecture: 3-step pipeline
  #
  #  Step 1 — PLANNING (AI, fast, cheap)
  #    Input : user prompt + survey title/description/questions list + data summary
  #    Output: report_mode + sections[] each with charts[] spec
  #    AI decides: what sections, what charts, what chart types, what order
  #
  #  Step 2 — DATA BUILDING (Ruby, deterministic)
  #    For each chart in the plan, pull exact numbers from DB
  #    Build cross-tab data, distributions, etc.
  #
  #  Step 3 — WRITING (AI, optional — skipped for focused mode)
  #    For each section, write a 2-3 sentence insight grounded in the actual data
  #    Also write executive summary + recommendations if report_mode = "full"
  #
  # ═══════════════════════════════════════════════════════════════════════════

  def perform(job_id)
    job    = AiJob.find(job_id)
    survey = Survey.find(job.resource_id)
    job.start!

    @language    = job.input_data["language"] || "vi"
    language     = @language
    lang_name    = language == "vi" ? "Vietnamese" : "English"
    user_context = job.input_data["user_context"].presence
    report_format= job.input_data["format"].presence || "pdf"

    responses           = survey.responses.completed
    completed_ids       = responses.where(excluded: [false, nil]).pluck(:id)
    questions           = survey.questions.includes(:question_options).order(:position)

    valid_q_ids     = questions.pluck(:id).map(&:to_i).to_set
    choice_type_ids = questions.where(question_type: %w[single_choice dropdown])
                               .pluck(:id).map(&:to_i).to_set
    # A grouped "average comparison" cross-tab is only meaningful when the TARGET
    # is quantitative (rating/scale/% text). Comparing a choose-one question across
    # groups produces a misleading "agreement %" bar, so such targets are excluded.
    choice_target_ids = questions.where(question_type: %w[single_choice multiple_choice dropdown])
                                 .pluck(:id).map(&:to_i).to_set

    # ── Step 1: DATA BUILDING (before planning so AI sees real data) ────────
    all_chart_data = build_question_chart_data(survey, completed_ids)
    chart_data_by_qid = all_chart_data.index_by { |d| d["question_id"].to_i }

    # ── Step 2: PLANNING (with full data context) ────────────────────────────
    plan = call_planning_ai(
      survey:          survey,
      questions:       questions,
      user_context:    user_context,
      lang_name:       lang_name,
      total_responses: responses.count,
      chart_data:      chart_data_by_qid
    )

    # Collect all cross-tab pairs from the plan
    cross_tab_pairs = []
    Array(plan["sections"]).each do |sec|
      Array(sec["charts"]).each do |c|
        next unless c["cross_tab_by"].present? && c["question_id"].present?
        tid = c["question_id"].to_i
        gid = c["cross_tab_by"].to_i
        next unless valid_q_ids.include?(tid) && valid_q_ids.include?(gid) && choice_type_ids.include?(gid)
        next if choice_target_ids.include?(tid) # skip meaningless choose-one cross-tabs
        cross_tab_pairs << { "target_id" => tid, "group_by_id" => gid, "label" => c["title"].to_s }
      end
    end
    cross_tab_pairs.uniq! { |p| "#{p['target_id']}_#{p['group_by_id']}" }

    cross_tab_map = cross_tab_pairs.any? ?
      build_cross_tab_data(survey, cross_tab_pairs, completed_ids) : {}

    total_responses = responses.count

    # Attach data to each chart in the plan
    Array(plan["sections"]).each do |sec|
      Array(sec["charts"]).each do |c|
        qid = c["question_id"]&.to_i
        next unless qid && qid > 0

        base = chart_data_by_qid[qid]&.dup
        next unless base

        # If planning AI chose a visual chart for a text question with no options, categorize via AI
        if c["chart_type"] != "quotes" && base["options"].blank? && base["texts"].present?
          themes = ReportAnalytics.categorize_themes(base["texts"], c["title"].to_s, total: total_responses, language: @language)
          if themes.any?
            base["options"] = themes
            base["type"]    = "multiple_choice"
          else
            c["chart_type"] = "quotes"
          end
        end

        c["data"] = base

        if c["cross_tab_by"].present?
          xt = cross_tab_map[qid]
          c["cross_tab_data"] = xt if xt
          # Force grouped_bar if cross_tab data exists and type not overridden
          c["chart_type"] ||= "grouped_bar"
        end
      end
    end

    # Drop cross-tab charts that target a choose-one question (no valid cross-tab
    # data could be attached) so they don't render as empty/misleading, then drop
    # any section left without charts.
    Array(plan["sections"]).each do |sec|
      sec["charts"] = Array(sec["charts"]).reject do |c|
        c["cross_tab_by"].present? && c["cross_tab_data"].blank? &&
          choice_target_ids.include?(c["question_id"].to_i)
      end
    end
    plan["sections"] = Array(plan["sections"]).reject { |sec| Array(sec["charts"]).empty? }

    # ── Step 3: WRITING (skip for focused mode) ─────────────────────────────
    report_mode = plan["report_mode"].to_s
    if report_mode != "focused"
      data_for_writing = build_data_summary_for_writing(plan, all_chart_data, cross_tab_map, questions)
      writing_result   = call_writing_ai(
        survey:        survey,
        plan:          plan,
        data_summary:  data_for_writing,
        user_context:  user_context,
        lang_name:     lang_name,
        responses:     responses
      )

      # Merge writing results into plan
      plan["executive_summary"] = writing_result["executive_summary"]
      plan["conclusion"]        = writing_result["conclusion"]
      plan["recommendations"]   = writing_result["recommendations"] || []

      Array(writing_result["section_insights"]).each_with_index do |insight, i|
        plan["sections"][i]["insight"] = insight if plan["sections"][i]
      end
    else
      # Focused mode: build a 1-sentence insight from data only (no AI needed)
      plan["executive_summary"] = nil
      plan["recommendations"]   = []
      plan["focused_insight"]   = build_focused_insight(plan, cross_tab_map)
    end

    # ── Save ────────────────────────────────────────────────────────────────
    output = plan.merge(
      "subtitle"     => language == "en" ? "#{Date.current.strftime('%m/%Y')} — #{responses.count} responses" : "#{Date.current.strftime('%m/%Y')} — #{responses.count} phản hồi",
      "response_count" => responses.count,
      "_meta"        => { "format" => report_format, "focused" => (report_mode == "focused"), "language" => @language }
    )

    ai_result = AiAnalysisResult.create!(
      workspace:      job.workspace,
      ai_job:         job,
      result_type:    "executive_report",
      resource_type:  "Survey",
      resource_id:    survey.id,
      output:         output,
      credits_cost:   job.credits_cost,
      response_count: responses.count
    )
    job.complete!(ai_result.id)

  rescue => e
    Rails.logger.error "AiExecutiveReportJob error: #{e.class} #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    job.fail!(e.message.truncate(500))
  end

  private

  # ── Step 1: Planning AI call ───────────────────────────────────────────────
  def call_planning_ai(survey:, questions:, user_context:, lang_name:, total_responses:, chart_data: {})
    # Build rich question catalog with real data so AI can match user intent precisely
    questions_catalog = questions.each_with_index.map { |q, i|
      cd   = chart_data[q.id]
      info = "  Q#{i+1} (ID #{q.id}) [#{q.question_type}] #{q.title}"
      if cd
        case cd["type"]
        when "single_choice", "multiple_choice", "dropdown"
          top = Array(cd["options"]).sort_by { |o| -o["count"].to_i }.first(6)
                  .map { |o| "#{o['label']}=#{o['count']}" }.join(", ")
          info += "\n    → Data: #{cd['total']} responses. Top options: #{top}"
          info += " [SUITABLE FOR: doughnut (≤6 opts), hbar (>6 opts), grouped_bar comparison]"
        when "multiple_choice"
          top = Array(cd["options"]).sort_by { |o| -o["count"].to_i }.first(6)
                  .map { |o| "#{o['label']}=#{o['count']}" }.join(", ")
          info += "\n    → Data: #{cd['total']} responses. Options: #{top} [SUITABLE FOR: hbar]"
        when "linear_scale", "rating", "nps"
          info += "\n    → Data: avg=#{cd['avg']}/#{cd['max']}, n=#{cd['total']}"
          info += " [SUITABLE FOR: #{cd['type'] == 'nps' ? 'nps' : 'rating_dist'}, dist_bar, grouped_bar comparison]"
          if cd["subtype"] == "pct"
            info += " [% data — dist_bar histogram]"
          end
        when "short_text", "long_text"
          if cd["options"].present?
            top = Array(cd["options"]).first(5).map { |o| "#{o['label']}=#{o['count']}" }.join(", ")
            info += "\n    → Data: #{cd['total']} text answers aggregated as options: #{top}"
            info += " [SUITABLE FOR: doughnut, hbar]"
          else
            sample = Array(cd["texts"]).first(2).map { |t| "\"#{t.to_s.truncate(60)}\"" }.join(", ")
            info += "\n    → Data: #{cd['total']} text answers. Samples: #{sample} [SUITABLE FOR: hbar (AI will group into themes) OR quotes (if user wants raw text)]"
          end
        end
      else
        info += "\n    → No data available"
      end
      info
    }.join("\n")

    system_prompt = <<~SYS.strip
      You are an expert survey data analyst and visualization planner.
      Your job: deeply understand the user's request, match it to the correct survey questions and data, then design the optimal chart structure.

      CRITICAL PRINCIPLE: Match user intent precisely.
      - "tỷ lệ" / "proportion" / "ratio" → doughnut or hbar showing percentages
      - "so sánh" / "giữa các" / "theo bộ phận" → grouped_bar with cross_tab_by
      - "trung bình" / "average" / "điểm" → rating_dist or number
      - "xu hướng" / "phân bổ" / "distribution" → dist_bar
      - "nhận xét" / "ý kiến" / "quote" → quotes
      - "hình tròn" / "pie" / "donut" → doughnut
      - "cột" / "bar" → hbar or dist_bar
      - "tiết kiệm thời gian" / "time saved" → look for % or numeric questions about time saving
      - "tool AI" / "công cụ AI" / "phần mềm" → look for questions about AI tools used

      OUTPUT ONLY valid JSON. No markdown, no explanation.
    SYS

    user_prompt = <<~PROMPT
      ## User's request (in their own words)
      #{user_context.present? ? "\"#{user_context}\"" : "(no specific request — create a comprehensive full report)"}

      ## Survey context
      Title: #{survey.title}
      #{survey.description.present? ? "Description: #{survey.description}" : ""}
      Total responses: #{total_responses}

      ## Available questions WITH ACTUAL DATA
      (Use question IDs exactly as shown when referencing in charts)
      #{questions_catalog}

      ## CHART TYPE REFERENCE
      - "doughnut"    → pie/circle chart showing proportions. Use when: user says "hình tròn/pie/tỷ lệ" AND question has ≤8 distinct options
      - "hbar"        → horizontal bar chart. Use when: many options (>6), or user says "cột ngang", or comparing multiple choice
      - "dist_bar"    → vertical histogram. Use when: numeric/% distribution, user says "phân bổ/distribution"
      - "rating_dist" → rating scale breakdown. Use when: 1-5 or 1-10 rating question
      - "nps"         → NPS chart. ONLY for 0-10 recommendation questions
      - "grouped_bar" → grouped comparison. REQUIRES cross_tab_by. Use when: "so sánh theo X / X giữa các nhóm Y"
      - "number"      → big single KPI. Use when: user wants one key metric (avg, total, %)
      - "quotes"      → show text quotes. Use when: user explicitly wants to see raw comments/opinions. For open-ended text questions, prefer "hbar" when user asks for chart/biểu đồ/thống kê — the system will auto-group responses into themes.
      - "bar"         → vertical bar. Use when: ordered categorical data

      ## OUTPUT LANGUAGE
      ALL text (report_title, section titles, chart titles) MUST be in #{lang_name}.
      Do NOT output English titles if language is Vietnamese.

      ## TASK
      Step 1 — Understand what the user wants: which metric, which question, which visual format
      Step 2 — Match to the correct question ID(s) above
      Step 3 — Select the right chart_type (follow user's explicit format request if given)
      Step 4 — Output the minimal structure

      ## HARD RULES (avoid basic mistakes)
      1. The chart "title" MUST describe the SAME question you put in "question_id".
         Never write a title about topic A while pointing question_id at question B.
         If unsure, base the title on that question's actual wording above.
      2. "chart_type" MUST be one of the types in that question's [SUITABLE FOR: ...] hint.
         Do NOT pick a type the question's data cannot fill (e.g. hbar needs options;
         quotes needs raw text; rating_dist/dist_bar/nps need a numeric scale).
      3. Do NOT create more than ONE chart for the same question_id — EXCEPT you may add
         one extra grouped_bar (cross_tab_by) comparison for a quantitative question.
      4. Only reference question IDs that appear in the catalog above.

      report_mode rules:
      - "focused": user says "nhanh/quick/chỉ cần/only/just/một chart/1 biểu đồ" → 1 section, 1-2 charts
      - "full": user wants overview/toàn bộ/comprehensive → 2-5 sections

      Return JSON ONLY:
      {
        "report_mode": "focused|full",
        "report_title": "<title in #{lang_name} matching what user asked — NOT the survey title>",
        "sections": [
          {
            "title": "<section heading ≤5 words in #{lang_name}>",
            "charts": [
              {
                "question_id": <int — MUST match an ID from the catalog above>,
                "chart_type": "<one of: doughnut|hbar|dist_bar|rating_dist|nps|grouped_bar|number|quotes|bar>",
                "title": "<chart title ≤6 words in #{lang_name}>",
                "span": "<full|half>",
                "cross_tab_by": <question_id of grouping question OR null>
              }
            ]
          }
        ]
      }

      span rules: "half" for doughnut/number/rating_dist/nps; "full" for everything else.
      cross_tab_by rules:
      - ONLY set for grouped_bar. The grouping question (cross_tab_by) must be a single_choice/dropdown.
      - The chart's own question_id (the TARGET being compared) MUST be quantitative:
        a rating / linear_scale / nps question, or a short_text question that holds a number/percent.
      - NEVER cross-tab a choose-one / multiple-choice question across groups (e.g. "which stage is
        most effective by department") — averaging a categorical answer is meaningless. For those,
        just show one normal doughnut/hbar of the whole question instead.
    PROMPT

    raw    = ClaudeService.for_feature("survey_report").call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 2000)
    result = parse_json_response(raw.to_s)

    # Validate + sanitize
    result["report_mode"] = "full" unless %w[focused full].include?(result["report_mode"])
    result["sections"]    = Array(result["sections"])
    by_id = questions.index_by(&:id)
    result["sections"].each do |sec|
      sec["charts"] = Array(sec["charts"]).select { |c|
        c["question_id"].present? && by_id.key?(c["question_id"].to_i)
      }
      # Guard against the AI picking a chart_type the question's data can't fill
      # (e.g. hbar on a numeric question, quotes on a rating question). Correct it
      # to a data-appropriate type so blocks never render empty.
      sec["charts"].each do |c|
        next if c["cross_tab_by"].present? # grouped_bar handled by cross-tab logic
        cd = chart_data[c["question_id"].to_i]
        allowed = data_chart_types(cd)
        c["chart_type"] = allowed.first unless allowed.include?(c["chart_type"])
      end
    end
    result["sections"].reject! { |s| s["charts"].blank? }
    result

  rescue => e
    Rails.logger.error "Planning AI call failed: #{e.message}"
    # Fallback plan: show all metric questions grouped by department if found
    fallback_plan(survey, questions, user_context)
  end

  # Chart types whose required data actually exists for a question (best-fit first).
  def data_chart_types(cd)
    return %w[quotes] if cd.nil?
    case cd["type"]
    when "single_choice", "dropdown"
      has = Array(cd["options"]).any? { |o| o["count"].to_i > 0 }
      has ? (Array(cd["options"]).size <= 6 ? %w[doughnut hbar bar] : %w[hbar bar doughnut]) : %w[number]
    when "multiple_choice"
      %w[hbar bar doughnut]
    when "nps"
      %w[nps dist_bar]
    when "rating"
      %w[rating_dist dist_bar]
    when "linear_scale"
      cd["subtype"] == "pct" ? %w[dist_bar] : %w[rating_dist dist_bar]
    when "short_text", "long_text"
      if Array(cd["options"]).any? then %w[hbar bar doughnut]
      elsif Array(cd["texts"]).any? then %w[quotes hbar]
      else %w[quotes] end
    else
      %w[hbar dist_bar quotes]
    end
  end

  # ── Step 3: Writing AI call ────────────────────────────────────────────────
  def call_writing_ai(survey:, plan:, data_summary:, user_context:, lang_name:, responses:)
    sections_for_writing = Array(plan["sections"]).map { |sec|
      charts_desc = Array(sec["charts"]).map { |c|
        title = c["title"].to_s
        if c["cross_tab_data"]
          groups = c["cross_tab_data"]["groups"] || []
          sorted = groups.sort_by { |g| -(g["avg"] || g["pct"] || 0).to_f }
          top    = sorted.first
          bot    = sorted.last
          unit   = c["cross_tab_data"]["max"].to_i >= 50 ? "%" : ""
          "  - #{title}: #{sorted.map { |g| "#{g['label']}=#{g['avg'] || g['pct']}#{unit}" }.join(', ')}"
        elsif c["data"]
          d = c["data"]
          avg_s = d["avg"] ? " avg=#{d['avg']}/#{d['max']}" : ""
          "  - #{title}:#{avg_s} n=#{d['total']}"
        else
          "  - #{title}"
        end
      }.join("\n")
      "Section: #{sec['title']}\n#{charts_desc}"
    }.join("\n\n")

    system_prompt = <<~SYS.strip
      You are a survey analyst writing data-backed insights. Write in #{lang_name}.
      Every sentence must cite a specific number from the data provided.
      Return ONLY valid JSON. No markdown fences.
    SYS

    n_sections = Array(plan["sections"]).size
    mode = plan["report_mode"]

    user_prompt = <<~PROMPT
      ## Survey: #{survey.title}
      #{survey.description.present? ? "Description: #{survey.description}" : ""}
      #{user_context.present? ? "Requester's focus: \"#{user_context}\"" : ""}
      Total responses: #{responses.count}

      ## Actual data per section/chart
      #{sections_for_writing}

      ## Write in #{lang_name}:

      {
        "executive_summary": #{mode == "focused" ? "null" : '"2 sentences max. The single most important finding with exact number from data."'},
        "section_insights": [
          #{n_sections == 1 ? '"1 sentence insight for the section with key number."' : n_sections.times.map { |i| '"2-3 sentences. Key finding with exact numbers for section #{i+1}."' }.join(",\n          ")}
        ],
        "recommendations": #{mode == "focused" ? "[]" : '[{"priority":"high|medium","action":"Who + what + by when","rationale":"cite question data","expected_impact":"measurable result"}]  // 1-3 items'},
        "conclusion": #{mode == "focused" ? "null" : '"1 forward-looking sentence."'}
      }

      Rules:
      - Every number MUST come from the data above. No invention.
      - section_insights array must have exactly #{n_sections} element(s).
      - #{mode == "focused" ? "focused mode: only section_insights needed, rest null/[]" : "full mode: write all fields"}
    PROMPT

    raw    = ClaudeService.for_feature("survey_report").call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 1500)
    parse_json_response(raw.to_s)

  rescue => e
    Rails.logger.error "Writing AI call failed: #{e.message}"
    { "executive_summary" => nil, "section_insights" => [], "recommendations" => [], "conclusion" => nil }
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  def build_data_summary_for_writing(plan, all_chart_data, cross_tab_map, questions)
    # Already embedded in plan sections - no extra processing needed
    plan
  end

  def build_focused_insight(plan, cross_tab_map)
    first_chart = Array(plan["sections"]).flat_map { |s| s["charts"] }.first
    return nil unless first_chart

    xt = first_chart["cross_tab_data"] || cross_tab_map[first_chart["question_id"].to_i]
    return nil unless xt && xt["groups"].any?

    sorted = xt["groups"].sort_by { |g| -(g["avg"] || g["pct"] || 0).to_f }
    top    = sorted.first
    bot    = sorted.last
    unit   = xt["max"].to_i >= 50 ? "%" : "/#{xt['max']}"
    top_v  = top["avg"] || top["pct"]
    bot_v  = bot["avg"] || bot["pct"]
    gap    = ((top_v.to_f - bot_v.to_f).abs).round(1)

    if @language == "en"
      "#{top['label']} leads with #{top_v}#{unit}, #{gap}#{unit} above #{bot['label']}. " \
      "Overall average: #{first_chart.dig('data', 'avg')}#{unit} across #{first_chart.dig('data', 'total')} responses."
    else
      "#{top['label']} dẫn đầu với #{top_v}#{unit}, cao hơn #{bot['label']} #{gap}#{unit}. " \
      "Trung bình chung: #{first_chart.dig('data', 'avg')}#{unit} trên #{first_chart.dig('data', 'total')} phản hồi."
    end
  end

  def fallback_plan(survey, questions, user_context)
    metric_qs = questions.select { |q| %w[rating nps linear_scale short_text long_text].include?(q.question_type) }
    group_q   = questions.find { |q| %w[single_choice dropdown].include?(q.question_type) }
    charts = metric_qs.first(3).map { |q|
      c = { "question_id" => q.id, "chart_type" => default_chart_type(q), "title" => q.title.truncate(40), "span" => "half" }
      c["cross_tab_by"] = group_q.id if group_q
      c["chart_type"] = "grouped_bar" if group_q
      c["span"] = "full" if group_q
      c
    }
    {
      "report_mode"  => "full",
      "report_title" => survey.title,
      "sections"     => [{ "title" => @language == "en" ? "Overview" : "Tổng quan", "charts" => charts }]
    }
  end

  def default_chart_type(q)
    case q.question_type
    when "nps"                        then "nps"
    when "rating"                     then "rating_dist"
    when "linear_scale"               then "dist_bar"
    when "single_choice", "dropdown"  then "doughnut"
    when "multiple_choice"            then "hbar"
    else "dist_bar"
    end
  end

  # ── Build question chart data from DB ──────────────────────────────────────
  # Shared primitive (robust int/string option_ids match) — see ReportAnalytics.
  def option_match(option_id) = ReportAnalytics.option_match(option_id)

  def build_question_chart_data(survey, completed_response_ids = nil)
    completed_response_ids ||= survey.responses.completed.where(excluded: [false, nil]).pluck(:id)
    return [] if completed_response_ids.empty?

    survey.questions.order(:position).filter_map do |q|
      base = Answer.where(question: q, response_id: completed_response_ids)

      case q.question_type.to_sym
      when :single_choice, :multiple_choice, :dropdown
        total = base.count
        next if total == 0
        options = q.question_options.order(:position).map do |opt|
          count = base.where(*option_match(opt.id)).count
          { "id" => opt.id, "label" => opt.label, "count" => count,
            "pct" => (count.to_f / total * 100).round(1) }
        end
        { "question_id" => q.id, "question" => q.title,
          "type" => q.question_type.to_s, "total" => total, "options" => options }

      when :rating, :nps, :linear_scale
        nums = base.where.not(numeric_value: nil).pluck(:numeric_value).map(&:to_f)
        next if nums.empty?
        rs = ReportAnalytics.rating_stats(nums, q.question_type, q.settings)
        { "question_id" => q.id, "question" => q.title,
          "type" => q.question_type.to_s, "total" => rs[:total],
          "avg" => rs[:avg], "max" => rs[:max],
          "distribution" => rs[:dist].map { |d| { "value" => d[:value], "count" => d[:count] } } }

      when :short_text, :long_text
        texts = base.where.not(text_value: [nil, ""]).pluck(:text_value)
        next if texts.empty?
        nums = texts.filter_map { |t| t.to_s.gsub(/[~≈]/, "").scan(/\d+(?:\.\d+)?/).first&.to_f }
                    .select { |n| n > 0 && n <= 100 }
        if nums.size >= texts.size * 0.5
          avg  = (nums.sum / nums.size).round(1)
          dist = [[0,20],[21,40],[41,60],[61,80],[81,100]].map do |lo, hi|
            { "value" => "#{lo}–#{hi}%", "count" => nums.count { |n| n >= lo && n <= hi } }
          end
          { "question_id" => q.id, "question" => q.title,
            "type" => "linear_scale", "subtype" => "pct",
            "total" => nums.size, "avg" => avg, "max" => 100, "distribution" => dist }
        else
          # Tool-name aggregation only when the QUESTION is actually about which
          # tools people use — otherwise a suggestion mentioning "Claude" would be
          # naively split into junk "tool" rows. Let real open-ended questions fall
          # through to AI theme grouping instead.
          title_is_tools = q.title.match?(/\b(ai nào|công cụ|tool|phần mềm)\b/i)
          tool_hits = texts.select { |t| t.match?(/claude|chatgpt|gemini|gpt|cursor|copilot|codex|deepseek|midjourney|perplexity|trae|antigravity/i) }
          if title_is_tools && tool_hits.size >= [texts.size * 0.4, 2].max
            opts = SurveyReportSemantics.aggregate_tools(texts, texts.size)
            { "question_id" => q.id, "question" => q.title,
              "type" => "multiple_choice", "total" => texts.size,
              "options" => opts.map { |o| { "label" => o[:label], "count" => o[:count], "pct" => o[:pct] } },
              "texts" => texts.sample(6) }
          else
            { "question_id" => q.id, "question" => q.title,
              "type" => q.question_type.to_s, "total" => texts.size,
              "texts" => texts.sample(6) }
          end
        end
      end
    end.compact
  end

  # ── Build cross-tab data ───────────────────────────────────────────────────
  def build_cross_tab_data(survey, pairs, completed_response_ids)
    result = {}
    pairs.each do |pair|
      target_q = survey.questions.find_by(id: pair["target_id"].to_i)
      group_q  = survey.questions.find_by(id: pair["group_by_id"].to_i)
      next unless target_q && group_q

      # Single source of truth — only quantitative targets, dynamic scale,
      # robust option matching, small-sample flags (see ReportAnalytics).
      xt = ReportAnalytics.cross_tab(group_q, target_q, completed_response_ids)
      next unless xt

      result[target_q.id] = {
        "label"           => (pair["label"] || "So sánh theo nhóm").truncate(60),
        "group_question"  => xt[:group_question].to_s.truncate(60),
        "type"            => xt[:target_type],
        "max"             => xt[:max],
        "low_confidence"  => xt[:low_confidence_overall],
        "groups"          => xt[:groups].map { |g|
          { "label" => g[:label], "avg" => g[:value], "total" => g[:n],
            "max" => xt[:max], "low_confidence" => g[:low_confidence] }
        }
      }
    end
    result
  end

  # ── JSON parsing ───────────────────────────────────────────────────────────
  def parse_json_response(text)
    clean    = text.gsub(/\A\s*```(?:json)?\s*/i, "").gsub(/\s*```\s*\z/, "").strip
    json_str = clean.match(/\{.*\}/m)&.to_s || clean

    begin; return JSON.parse(json_str); rescue JSON::ParserError; end
    begin; return JSON.parse(fix_json_strings(json_str)); rescue JSON::ParserError; end
    begin; return JSON.parse(json_str.gsub(/[\x00-\x1F\x7F]/, '')); rescue JSON::ParserError => e
      raise "Could not parse AI response as JSON: #{e.message.truncate(200)}"
    end
  end

  def fix_json_strings(s)
    out = String.new(encoding: "UTF-8"); in_str = false; i = 0
    while i < s.length
      c = s[i]
      if in_str
        case c
        when "\\" then out << c << (s[i+1] || ""); i += 2; next
        when '"'  then in_str = false; out << c
        when "\n" then out << '\\n'
        when "\r" then out << '\\r'
        when "\t" then out << '\\t'
        else out << c
        end
      else
        out << c; in_str = true if c == '"'
      end
      i += 1
    end
    out
  end

  # Theme categorization now lives in ReportAnalytics.categorize_themes (shared).
end
