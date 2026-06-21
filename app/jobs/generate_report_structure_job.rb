class GenerateReportStructureJob < ApplicationJob
  queue_as :default

  INSIGHTS_SYSTEM_PROMPT = <<~PROMPT.freeze
    Bạn là chuyên gia phân tích dữ liệu khảo sát. Nhiệm vụ duy nhất của bạn là sinh ra
    các insights thông minh, súc tích dựa trên dữ liệu thực. Chỉ trả về JSON array thuần túy.
  PROMPT

  # Legacy — kept for reference but no longer used for structure generation
  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are an expert survey data visualization & analysis designer.
    Given a survey's questions AND their actual aggregated response data, you will:
    1. Design the optimal visual report structure (sections + charts)
    2. Generate smart, data-backed insights and recommendations

    Respond ONLY with valid JSON — no markdown fences, no explanation.

    === CHART TYPES ===
    - "doughnut"              — single_choice/dropdown ≤8 options
    - "bar"                   — choice question >8 options OR any multi-select/tool question
    - "horizontal_bar"        — multiple_choice pain points / challenges
    - "distribution_bar"      — questions where answers are PERCENTAGES (savings, rates) — uses histogram buckets
    - "rating_bar"            — rating/linear_scale (horizontal bars, shows avg score)
    - "nps_bar"               — NPS 0–10 with colored bars (red=detractor, cyan=passive, green=promoter)
    - "quotes"                — long_text notable responses
    - "theme_bar"             — long_text suggestions → keyword-grouped bar
    - "number"                — single summary metric

    === PROCESSING HINTS ===
    - "normalize_tools"  — question asking which AI/software tools are used
    - "parse_percent"    — short_text where answer is a % number (savings, completion rate)
    - "extract_themes"   — long_text suggestions → group into themes

    === CROSS-TAB CARDS (question_id = null) ===
    Use when a grouping question (dept, role) + numeric/percent questions exist.
    Add as a card:
    {"question_id": null, "chart_type": "cross_tab_grouped_bar", "title": "...",
     "group_by_question_id": <dept_q_id>, "value_question_ids": [<id1>, <id2>],
     "processing": "parse_percent", "span": 12}

    === AI INSIGHTS ===
    Generate 2–5 data-backed insights. Two types:
    - type "stat": a key finding with exact numbers from the data
    - type "recommendation": an actionable step with title + rationale citing exact data

    === KPI SOURCES ===
    - "total_responses", "question_avg", "question_avg_pct", "question_top_option"

    === OUTPUT FORMAT ===
    {
      "kpis": [
        {"label": "...", "source": "total_responses", "color": "#4361ee"},
        {"label": "...", "source": "question_avg_pct", "question_id": 5, "color": "#06b6d4"}
      ],
      "sections": [
        {
          "id": "s1",
          "title": "Section title",
          "layout": "grid-2",
          "cards": [
            {"question_id": 2, "chart_type": "doughnut", "title": "Card title", "span": 6},
            {"question_id": 3, "chart_type": "bar", "processing": "normalize_tools", "title": "Card title", "span": 6},
            {"question_id": null, "chart_type": "cross_tab_grouped_bar", "title": "...",
             "group_by_question_id": 2, "value_question_ids": [5, 6], "processing": "parse_percent", "span": 12}
          ]
        }
      ],
      "ai_insights": [
        {"type": "stat", "text": "Exact number + what it means — cite the data"},
        {"type": "recommendation", "title": "Who does what by when", "detail": "Cite which question data led to this recommendation"}
      ]
    }

    Rules:
    - All text in same language as survey questions
    - span 6 = half width, span 12 = full width
    - distribution_bar/cross_tab/quotes → span 12 preferred; doughnut/bar → span 6
    - 2–6 sections, 2–5 cards per section
    - Every insight MUST reference actual numbers from the data provided
    - Recommendations must be specific: WHO + WHAT + concrete basis from data
  PROMPT

  def perform(survey_id, language = "vi")
    language = language.presence_in(%w[vi en]) || "vi"
    survey = Survey.find_by(id: survey_id)
    return unless survey

    questions = survey.questions.includes(:question_options).order(:position)
    return if questions.empty?

    completed_ids = survey.responses.completed.where(excluded: [false, nil]).pluck(:id)

    # ── Step 1: Ruby semantic detection builds structure deterministically ──
    semantics_builder = SurveyReportSemantics.new(survey, completed_ids)
    structure         = semantics_builder.build_structure
    data_summary      = semantics_builder.data_summary_for_ai

    # ── Step 1b: Let the AI decide section grouping + order (dynamic, no fixed
    # 6-bucket template). Falls back to the deterministic grouping on any failure.
    begin
      grouping = plan_sections(semantics_builder.chartable_catalog, survey, language)
      if grouping
        regrouped = semantics_builder.build_sections_from_grouping(grouping)
        structure["sections"] = regrouped if regrouped.present?
      end
    rescue => e
      Rails.logger.warn "GenerateReportStructureJob: section planner failed, using deterministic grouping: #{e.message}"
    end

    Rails.logger.info "GenerateReportStructureJob: survey #{survey_id} — #{structure['sections']&.length} sections, now calling AI for insights"

    # ── Step 2: AI shortens labels + generates insights ───────────────────
    # Collect all texts needing shortening
    kpi_texts = structure["kpis"].map { |k| k["label"] }

    # For section naming, give the AI the actual questions inside each section so
    # it names them by CONTENT (domain-agnostic) rather than shortening a
    # hardcoded seed title. Cross-tab cards expose value_question_ids instead.
    qmap = questions.index_by(&:id)
    section_questions = structure["sections"].map do |s|
      s["cards"].flat_map { |c|
        if c["question_id"]
          [qmap[c["question_id"].to_i]&.title]
        else
          Array(c["value_question_ids"]).map { |id| qmap[id.to_i]&.title }
        end
      }.compact.map { |t| t.to_s.truncate(60) }.uniq.first(6)
    end

    card_texts = structure["sections"].flat_map { |s|
      s["cards"].map { |c| c["title"].to_s }
    }

    output_lang     = language == "vi" ? "Vietnamese (tiếng Việt)" : "English"
    task1_label     = language == "vi" ? "Rút gọn nhãn KPI (tối đa 4 từ, súc tích)" : "Shorten KPI labels (max 4 words, clear)"
    task2_label     = language == "vi" ? "Đặt tiêu đề section (≤5 từ) DỰA TRÊN nội dung các câu hỏi trong section — không bịa chủ đề ngoài dữ liệu" : "Name each section (≤5 words) BASED ON the questions it contains — do not invent topics not in the data"
    task3_label     = language == "vi" ? "Rút gọn tiêu đề card/chart (tối đa 6 từ)" : "Shorten chart titles (max 6 words)"
    task4_label     = language == "vi" ? "Insights thông minh (4–6 insights)" : "Smart insights (4–6 insights)"
    stat_desc       = language == "vi" ? "phát hiện quan trọng với số liệu cụ thể" : "key finding with specific data"
    rec_desc        = language == "vi" ? "đề xuất hành động WHO + WHAT + dẫn chứng số liệu" : "action recommendation WHO + WHAT + data evidence"
    return_label    = language == "vi" ? "Trả về JSON (không markdown):" : "Return JSON (no markdown):"
    title_task      = language == "en" ? "\n## Task 0 — Translate survey title to English (concise, max 10 words):\n\"#{survey.title}\"\n" : ""
    title_json      = language == "en" ? "\n  \"survey_title\": \"translated title here\"," : ""

    insights_prompt = <<~MSG
      ⚠️ LANGUAGE RULE: ALL output text (kpi_labels, section_titles, card_titles, insights) MUST be in #{output_lang}. Translate if needed. Do NOT mix languages.

      Survey: "#{survey.title}"
      Total responses: #{completed_ids.size}

      ## Data:
      #{data_summary}

      ---
      ## Task 1 — #{task1_label}:
      #{kpi_texts.map.with_index { |t, i| "#{i}: #{t}" }.join("\n")}

      ## Task 2 — #{task2_label}:
      #{section_questions.map.with_index { |qs, i| "#{i}: [#{qs.join(' | ')}]" }.join("\n")}

      ## Task 3 — #{task3_label}:
      #{card_texts.map.with_index { |t, i| "#{i}: #{t}" }.join("\n")}

      #{title_task}## Task 4 — #{task4_label}:
      - type "stat": #{stat_desc}
      - type "recommendation": #{rec_desc}

      #{return_label}
      {#{title_json}
        "kpi_labels": ["label 0", "label 1", ...],
        "section_titles": ["title 0", "title 1", ...],
        "card_titles": ["title 0", "title 1", ...],
        "ai_insights": [
          {"type": "stat", "text": "..."},
          {"type": "recommendation", "title": "...", "detail": "..."}
        ]
      }
    MSG

    raw      = ClaudeService.for_feature("survey_report").call(system_prompt: INSIGHTS_SYSTEM_PROMPT,
                                         user_prompt:   insights_prompt, max_tokens: 3000)
    json_str = raw.to_s.gsub(/\A```(?:json)?\s*|\s*```\z/, "").strip
    result   = JSON.parse(json_str)

    # Apply shortened KPI labels
    Array(result["kpi_labels"]).each_with_index do |lbl, i|
      structure["kpis"][i]["label"] = lbl.to_s.strip if structure["kpis"][i] && lbl.present?
    end

    # Apply shortened section titles
    Array(result["section_titles"]).each_with_index do |ttl, i|
      structure["sections"][i]["title"] = ttl.to_s.strip if structure["sections"][i] && ttl.present?
    end

    # Apply shortened card titles (flat index across all sections)
    if result["card_titles"].is_a?(Array)
      idx = 0
      structure["sections"].each do |sec|
        sec["cards"].each do |card|
          short = result["card_titles"][idx].to_s.strip
          card["title"] = short if short.present?
          idx += 1
        end
      end
    end

    insights = Array(result["ai_insights"]).select { |i| i["text"].present? || i["title"].present? }
    # Guard against fabricated numbers: drop a "stat" insight whose cited numbers
    # match NONE of the real computed values (strong hallucination signal).
    facts = build_fact_numbers(semantics_builder, completed_ids.size)
    structure["ai_insights"] = verify_insights(insights, facts)
    structure["survey_title_translated"] = result["survey_title"].to_s.strip if result["survey_title"].present?

    # ── AI theme label generation for text question cards ────────────────
    structure["sections"].each do |sec|
      sec["cards"].each do |card|
        next unless card["processing"].in?(%w[normalize_tools extract_themes])
        qid = card["question_id"]&.to_i
        next unless qid
        sem = semantics_builder.semantics[qid]
        texts = sem&.dig(:texts) || []
        next if texts.size < 3

        ai_options = ReportAnalytics.categorize_themes(texts, card["title"].to_s, total: texts.size, language: language)
        card["ai_options"] = ai_options if ai_options.present?
      rescue => e
        Rails.logger.warn "AI theme labels failed for Q#{qid}: #{e.message}"
      end
    end

    settings = survey.settings.to_h.merge(
      "report_structure_#{language}"         => structure,
      "report_structure_#{language}_version" => Time.current.to_i.to_s
    )
    survey.update_columns(settings: settings)
    Rails.logger.info "GenerateReportStructureJob: survey #{survey_id} [#{language}] done — #{structure['sections']&.length} sections, #{structure['ai_insights']&.length} insights"

  rescue JSON::ParserError => e
    Rails.logger.error "GenerateReportStructureJob JSON error survey #{survey_id}: #{e.message}\nRaw: #{raw.to_s.first(500)}"
    # Save structure without insights rather than full fallback
    if defined?(structure) && structure["sections"].present?
      structure["ai_insights"] = []
      survey.update_columns(settings: survey.settings.to_h.merge("report_structure_#{language}" => structure,
                                                                   "report_structure_#{language}_version" => Time.current.to_i.to_s))
    else
      save_fallback_structure(survey)
    end
  rescue => e
    Rails.logger.error "GenerateReportStructureJob error survey #{survey_id}: #{e.class} #{e.message}"
    save_fallback_structure(survey)
  end

  private

  # ── Insight number verification (anti-hallucination guard) ──────────────────
  def build_fact_numbers(builder, total)
    facts = [total.to_f]
    builder.semantics.each_value do |sem|
      facts << sem[:avg].to_f       if sem[:avg]
      facts << sem[:nps_score].to_f if sem[:nps_score]
      facts << sem[:total].to_f     if sem[:total]
      [sem[:min], sem[:max], sem[:promoters], sem[:passives], sem[:detractors]].each { |v| facts << v.to_f if v }
      Array(sem[:options]).each { |o| facts << o[:count].to_f if o[:count]; facts << o[:pct].to_f if o[:pct] }
      Array(sem[:distribution]).each { |d| c = d[:count] || d["count"]; facts << c.to_f if c }
      Array(sem[:dist]).each { |d| c = d["count"] || d[:count]; facts << c.to_f if c }
    end
    facts.uniq
  end

  def verify_insights(insights, facts)
    Array(insights).select do |ins|
      next true unless ins["type"] == "stat"
      nums = ins["text"].to_s.scan(/\d+(?:[.,]\d+)?/).map { |s| s.tr(",", ".").to_f }
      next true if nums.empty?
      grounded = nums.any? { |n| facts.any? { |f| (f - n).abs <= 1.0 || (f != 0 && ((f - n).abs / f.abs) <= 0.05) } }
      Rails.logger.warn "GenerateReportStructureJob: dropped unverified insight: #{ins['text'].to_s.truncate(90)}" unless grounded
      grounded
    end
  end

  # ── AI section planner: group + order chartable questions into sections ─────
  # Returns [{ "title" =>, "question_ids" => [..] }] or nil (→ deterministic).
  def plan_sections(catalog, survey, language)
    return nil if catalog.blank? || catalog.size < 3
    lang_name = language == "vi" ? "Vietnamese (tiếng Việt)" : "English"
    lines = catalog.map { |c| "  - id=#{c['id']} [#{c['role']}] #{c['title']}" }.join("\n")
    system = "You are a survey report designer. Group questions into a logical, well-ordered set " \
             "of report sections. Return ONLY valid JSON. Titles MUST be in #{lang_name}."
    user = <<~PROMPT
      Survey: "#{survey.title}"
      Questions (id, semantic role, title):
      #{lines}

      Group these into 2–6 sections that tell a coherent story, ordered logically
      (overview/segments first → core metrics → problems → suggestions last).
      - Every question id must appear in exactly one section.
      - Keep related questions together; don't make single-question sections unless necessary.
      - Section title: ≤5 words, in #{lang_name}, describing that section's questions.

      Return JSON ONLY:
      { "sections": [ { "title": "...", "question_ids": [1,2] }, ... ] }
    PROMPT
    raw = ClaudeService.for_feature("survey_report").call(system_prompt: system, user_prompt: user, max_tokens: 800)
    clean = raw.to_s.gsub(/\A\s*```(?:json)?\s*/i, "").gsub(/\s*```\s*\z/, "").strip
    parsed = JSON.parse(clean[/\{.*\}/m] || "{}")
    secs = parsed["sections"]
    return nil unless secs.is_a?(Array) && secs.any?
    valid_ids = catalog.map { |c| c["id"].to_i }.to_set
    # Keep only known ids; ensure uncovered questions are appended to the last section.
    seen = Set.new
    secs.each { |s| s["question_ids"] = Array(s["question_ids"]).map(&:to_i).select { |id| valid_ids.include?(id) && seen.add?(id) } }
    missing = valid_ids.to_a - seen.to_a
    secs.last["question_ids"] |= missing if missing.any? && secs.last
    secs.reject! { |s| s["question_ids"].blank? }
    secs.presence
  end

  def save_fallback_structure(survey)
    return unless survey
    questions = survey.questions.includes(:question_options).order(:position)
    groups    = questions.group_by { |q|
      case q.question_type
      when "single_choice", "multiple_choice", "dropdown" then "choice"
      when "rating", "linear_scale", "nps"                then "numeric"
      else "text"
      end
    }
    sections = []
    titles   = { "choice" => "Câu hỏi lựa chọn", "numeric" => "Đánh giá & chỉ số", "text" => "Phản hồi tự do" }
    groups.each_with_index do |(type, qs), i|
      cards = qs.map do |q|
        ct = case q.question_type
             when "single_choice", "dropdown" then "doughnut"
             when "multiple_choice"            then "horizontal_bar"
             when "nps"                        then "nps_bar"
             when "rating", "linear_scale"     then "rating_bar"
             else "quotes"
             end
        span = %w[short_text long_text].include?(q.question_type) ? 12 : 6
        { "question_id" => q.id, "chart_type" => ct, "title" => q.title.truncate(60), "span" => span }
      end
      sections << { "id" => "s#{i+1}", "title" => titles[type] || "Câu hỏi", "layout" => "grid-2", "cards" => cards }
    end
    kpis = [{ "label" => "Người tham gia", "source" => "total_responses", "color" => "#4361ee" }]
    structure = { "kpis" => kpis, "sections" => sections, "ai_insights" => [], "_fallback" => true }
    %w[vi en].each do |lang|
      survey.update_columns(settings: survey.settings.to_h.merge("report_structure_#{lang}" => structure,
                                                                  "report_structure_#{lang}_version" => Time.current.to_i.to_s))
    end
  end
end
