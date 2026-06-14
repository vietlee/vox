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

    language     = job.input_data["language"] || "vi"
    lang_name    = language == "vi" ? "Vietnamese" : "English"
    user_context = job.input_data["user_context"].presence
    report_format= job.input_data["format"].presence || "pdf"

    responses           = survey.responses.completed
    completed_ids       = responses.where(excluded: [false, nil]).pluck(:id)
    questions           = survey.questions.includes(:question_options).order(:position)

    valid_q_ids     = questions.pluck(:id).map(&:to_i).to_set
    choice_type_ids = questions.where(question_type: %w[single_choice dropdown])
                               .pluck(:id).map(&:to_i).to_set

    # ── Step 1: PLANNING ────────────────────────────────────────────────────
    plan = call_planning_ai(
      survey:        survey,
      questions:     questions,
      user_context:  user_context,
      lang_name:     lang_name,
      total_responses: responses.count
    )

    # ── Step 2: DATA BUILDING ───────────────────────────────────────────────
    all_chart_data = build_question_chart_data(survey, completed_ids)
    chart_data_by_qid = all_chart_data.index_by { |d| d["question_id"].to_i }

    # Collect all cross-tab pairs from the plan
    cross_tab_pairs = []
    Array(plan["sections"]).each do |sec|
      Array(sec["charts"]).each do |c|
        next unless c["cross_tab_by"].present? && c["question_id"].present?
        tid = c["question_id"].to_i
        gid = c["cross_tab_by"].to_i
        next unless valid_q_ids.include?(tid) && valid_q_ids.include?(gid) && choice_type_ids.include?(gid)
        cross_tab_pairs << { "target_id" => tid, "group_by_id" => gid, "label" => c["title"].to_s }
      end
    end
    cross_tab_pairs.uniq! { |p| "#{p['target_id']}_#{p['group_by_id']}" }

    cross_tab_map = cross_tab_pairs.any? ?
      build_cross_tab_data(survey, cross_tab_pairs, completed_ids) : {}

    # Attach data to each chart in the plan
    Array(plan["sections"]).each do |sec|
      Array(sec["charts"]).each do |c|
        qid = c["question_id"]&.to_i
        next unless qid && qid > 0

        base = chart_data_by_qid[qid]&.dup
        next unless base

        c["data"] = base

        if c["cross_tab_by"].present?
          xt = cross_tab_map[qid]
          c["cross_tab_data"] = xt if xt
          # Force grouped_bar if cross_tab data exists and type not overridden
          c["chart_type"] ||= "grouped_bar"
        end
      end
    end

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
      "subtitle"     => "#{Date.current.strftime('%m/%Y')} — #{responses.count} phản hồi",
      "response_count" => responses.count,
      "_meta"        => { "format" => report_format, "focused" => (report_mode == "focused") }
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
  def call_planning_ai(survey:, questions:, user_context:, lang_name:, total_responses:)
    questions_list = questions.each_with_index.map { |q, i|
      "  Q#{i+1} (ID #{q.id}) [#{q.question_type}] #{q.title}"
    }.join("\n")

    system_prompt = <<~SYS.strip
      You are a data visualization planner for survey reports.
      Your job: read the user's request + survey structure, then design the MINIMUM necessary report structure.

      KEY PRINCIPLE: The user asked for something specific. Give them exactly that — not a generic report.
      - If they want one chart: plan one section with one chart.
      - If they want a comparison: plan the comparison chart + minimal context.
      - If they want a full analysis: plan appropriate sections.

      OUTPUT ONLY valid JSON. No markdown, no explanation.
    SYS

    q_types_hint = {
      "single_choice" => "choice/dropdown — can group other questions by this",
      "multiple_choice" => "multi-select — show % per option",
      "rating" => "1-5 scale — show avg + distribution",
      "linear_scale" => "custom scale — show avg + distribution",
      "nps" => "0-10 satisfaction — show NPS summary",
      "short_text" => "if mostly %-numbers: treat as numeric; else: quotes",
      "long_text" => "qualitative — themes or quotes",
      "dropdown" => "choice — same as single_choice"
    }

    chart_types_guide = <<~GUIDE
      CHART TYPE GUIDE:
      - "grouped_bar"  → compare a metric across groups (REQUIRES cross_tab_by). Best for "X theo Y / X giữa các Y"
      - "dist_bar"     → histogram buckets for % estimates or numeric ranges
      - "rating_dist"  → horizontal bars for 1-5 or 1-10 scales, shows each value count
      - "nps"          → ONLY for 0-10 satisfaction/recommendation questions
      - "doughnut"     → proportions for single_choice ≤6 options
      - "hbar"         → horizontal bars for multi-choice or choice >6 options
      - "bar"          → vertical bars for ordered distributions
      - "number"       → single big KPI number (avg, %, count)
      - "quotes"       → long_text qualitative responses
    GUIDE

    user_prompt = <<~PROMPT
      ## User request
      #{user_context.present? ? "\"#{user_context}\"" : "(no specific request — create a comprehensive report)"}

      ## Survey
      Title: #{survey.title}
      #{survey.description.present? ? "Description: #{survey.description}" : ""}
      Total responses: #{total_responses}

      ## Questions available
      #{questions_list}

      #{chart_types_guide}

      ## Question type hints
      #{q_types_hint.map { |k,v| "- #{k}: #{v}" }.join("\n")}

      ## Language
      Output language: #{lang_name}. ALL text fields (report_title, section title, chart title) MUST be written in #{lang_name}. Do NOT use English if the language is Vietnamese.

      ## Your task
      Design the report structure. Determine:
      1. report_mode: "focused" (user wants 1-2 specific charts, quick answer) OR "full" (user wants comprehensive analysis)
      2. report_title: concise title in #{lang_name} reflecting exactly what the user asked for (NOT the survey title)
      3. sections: array of sections, each with charts

      Rules for report_mode:
      - "focused": user says "nhanh/quick/chỉ cần/only/just", or asks for ONE specific metric/chart
      - "full": user asks for full analysis, overview, or no specific constraint

      Rules for sections:
      - focused mode: 1 section max, 1-3 charts max
      - full mode: 2-5 sections, each covering a different analytical angle

      Rules for charts:
      - Each chart: {question_id, chart_type, title (≤6 words in #{lang_name}), span ("full"|"half"), cross_tab_by (optional)}
      - cross_tab_by: ID of a single_choice/dropdown question used to group the metric
      - If user wants "X theo/giữa Y": chart_type="grouped_bar", cross_tab_by=Y_question_id
      - If user says "biểu đồ hình tròn" or "pie chart" or "doughnut": use chart_type="doughnut"
      - If user says "biểu đồ cột" or "bar chart": use chart_type="hbar" or "dist_bar"
      - SKIP: identity/name questions, grouping-only questions (they appear as cross_tab_by axis)
      - span "full" for: grouped_bar, dist_bar, hbar with many options, quotes
      - span "half" for: doughnut, number, rating_dist, nps

      Return JSON:
      {
        "report_mode": "focused|full",
        "report_title": "...",
        "sections": [
          {
            "title": "Section heading (≤5 words)",
            "sections_purpose": "1 sentence: what analytical question this section answers",
            "charts": [
              {
                "question_id": <int>,
                "chart_type": "grouped_bar|dist_bar|rating_dist|nps|doughnut|hbar|bar|number|quotes",
                "title": "Chart title ≤6 words",
                "span": "full|half",
                "cross_tab_by": <int or null>
              }
            ]
          }
        ]
      }
    PROMPT

    raw    = ClaudeService.haiku.call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 1500)
    result = parse_json_response(raw.to_s)

    # Validate + sanitize
    result["report_mode"] = "full" unless %w[focused full].include?(result["report_mode"])
    result["sections"]    = Array(result["sections"])
    result["sections"].each do |sec|
      sec["charts"] = Array(sec["charts"]).select { |c|
        c["question_id"].present? &&
          questions.map(&:id).include?(c["question_id"].to_i)
      }
    end
    result["sections"].reject! { |s| s["charts"].blank? }
    result

  rescue => e
    Rails.logger.error "Planning AI call failed: #{e.message}"
    # Fallback plan: show all metric questions grouped by department if found
    fallback_plan(survey, questions, user_context)
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

    raw    = ClaudeService.sonnet.call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 1500)
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

    "#{top['label']} dẫn đầu với #{top_v}#{unit}, cao hơn #{bot['label']} #{gap}#{unit}. " \
    "Trung bình chung: #{first_chart.dig('data', 'avg')}#{unit} trên #{first_chart.dig('data', 'total')} phản hồi."
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
      "sections"     => [{ "title" => "Tổng quan", "charts" => charts }]
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
          count = base.where("option_ids @> ?", [opt.id.to_s].to_json).count
          { "id" => opt.id, "label" => opt.label, "count" => count,
            "pct" => (count.to_f / total * 100).round(1) }
        end
        { "question_id" => q.id, "question" => q.title,
          "type" => q.question_type.to_s, "total" => total, "options" => options }

      when :rating, :nps, :linear_scale
        nums = base.where.not(numeric_value: nil).pluck(:numeric_value).map(&:to_i)
        next if nums.empty?
        max_val = if q.nps? then 10
                  elsif q.question_type == "linear_scale"
                    q.settings&.dig("max_value")&.to_i.then { |v| v&.positive? ? v : 10 }
                  else 5
                  end
        avg  = (nums.sum.to_f / nums.size).round(1)
        dist = (1..max_val).map { |v| { "value" => v, "count" => nums.count(v) } }
        { "question_id" => q.id, "question" => q.title,
          "type" => q.question_type.to_s, "total" => nums.size,
          "avg" => avg, "max" => max_val, "distribution" => dist }

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
          # Check for tool-name data (people typed AI tool names)
          tool_hits = texts.select { |t| t.match?(/claude|chatgpt|gemini|gpt|cursor|copilot|codex|deepseek|midjourney|perplexity|trae|antigravity/i) }
          if tool_hits.size >= [texts.size * 0.2, 2].min
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

      group_options = group_q.question_options.order(:position)
      max_val = if target_q.nps? then 10
                elsif target_q.question_type == "linear_scale"
                  target_q.settings&.dig("max_value")&.to_i.then { |v| v&.positive? ? v : 10 }
                elsif %w[short_text long_text].include?(target_q.question_type) then 100
                else 5
                end

      groups = group_options.filter_map do |opt|
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
        when :short_text, :long_text
          texts = target_base.where.not(text_value: [nil, ""]).pluck(:text_value)
          next if texts.empty?
          nums = texts.filter_map { |t| t.to_s.gsub(/[~≈]/, "").scan(/\d+(?:\.\d+)?/).first&.to_f }
                      .select { |n| n > 0 && n <= 100 }
          next if nums.size < texts.size * 0.4
          avg = (nums.sum / nums.size).round(1)
          { "label" => opt.label.truncate(30), "avg" => avg, "total" => nums.size, "max" => 100 }
        when :single_choice, :multiple_choice, :dropdown
          total = target_base.count
          next if total == 0
          top = target_q.question_options.order(:position).map { |topt|
            cnt = target_base.where("option_ids @> ?", [topt.id.to_s].to_json).count
            { "option" => topt.label.truncate(30), "pct" => (cnt.to_f / total * 100).round(1) }
          }.max_by { |o| o["pct"] }
          { "label" => opt.label.truncate(30), "top_option" => top["option"], "pct" => top["pct"], "total" => total }
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
end
